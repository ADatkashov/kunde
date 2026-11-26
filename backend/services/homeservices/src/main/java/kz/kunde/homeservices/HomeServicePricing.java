package kz.kunde.homeservices;

import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.geo.Geo;
import kz.kunde.platform.geo.Point;
import kz.kunde.platform.partner.PartnerDirectory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Commercial rules of Home Services on top of the Booking Engine's list price: the venue's service zones and the offer's
 * surcharge tariff. One method prices both the public quote and the booking (through {@link HomeServicesBookingCategory}),
 * so the two cannot disagree. Writes are confined to the partner's own venues and need the catalogue capability.
 */
@Service
public class HomeServicePricing {
    public record Zone(String id, String venueId, String name, double centerLat, double centerLng, int radiusM, boolean active,
            long version) {}

    public record Tariff(String offerId, long callOutFeeMinor, int urgentSurchargePercent, int eveningSurchargePercent,
            String eveningFrom, long version) {}

    /** The amounts a customer pays above the list price, itemised; {@code totalMinor} includes the list price. */
    public record Quote(String offerId, long listPriceMinor, long callOutFeeMinor, long urgentSurchargeMinor,
            long eveningSurchargeMinor, long totalMinor, String currency, String zoneId) {}

    private static final String ZONE_COLUMNS = "z.id, z.venue_id, z.name, z.center_lat, z.center_lng, z.radius_m, z.active, z.version";

    private final JdbcTemplate db;
    private final PartnerDirectory partners;

    public HomeServicePricing(JdbcTemplate db, PartnerDirectory partners) {
        this.db = db;
        this.partners = partners;
    }

    // ---- pricing

    /** Surcharges for one booking or quote; refuses an address outside the venue's service area. */
    @Transactional(readOnly = true)
    public Charges charges(UUID venueId, UUID serviceId, long listPriceMinor, OffsetDateTime startsAt, java.time.ZoneId zone,
            Double latitude, Double longitude, boolean urgent) {
        String zoneId = requireServiceable(venueId, latitude, longitude);
        Optional<Object[]> tariff = db.query("""
                select t.call_out_fee_minor, t.urgent_surcharge_percent, t.evening_surcharge_percent, t.evening_from
                from marketplace.home_service_offers o join marketplace.home_service_tariffs t on t.offer_id = o.id
                where o.service_id = ? and o.status = 'PUBLISHED'
                """, (rs, row) -> new Object[] {rs.getLong(1), rs.getInt(2), rs.getInt(3), rs.getTime(4).toLocalTime()}, serviceId)
                .stream().findFirst();
        if (tariff.isEmpty()) {
            return new Charges(0, 0, 0, zoneId);
        }
        long callOut = (Long) tariff.get()[0];
        long urgentFee = urgent ? percentOf(listPriceMinor, (Integer) tariff.get()[1]) : 0;
        boolean evening = startsAt != null && !startsAt.atZoneSameInstant(zone).toLocalTime().isBefore((LocalTime) tariff.get()[3]);
        long eveningFee = evening ? percentOf(listPriceMinor, (Integer) tariff.get()[2]) : 0;
        return new Charges(callOut, urgentFee, eveningFee, zoneId);
    }

    public record Charges(long callOutFeeMinor, long urgentSurchargeMinor, long eveningSurchargeMinor, String zoneId) {
        public long totalMinor() { return callOutFeeMinor + urgentSurchargeMinor + eveningSurchargeMinor; }
    }

    private static long percentOf(long amount, int percent) {
        return Math.round(amount * percent / 100.0);
    }

    /** A venue without active zones serves the whole city; otherwise the address must lie inside one of them. */
    private String requireServiceable(UUID venueId, Double latitude, Double longitude) {
        List<Object[]> zones = db.query("select id, center_lat, center_lng, radius_m from marketplace.home_service_zones "
                + "where venue_id = ? and active order by name, id",
                (rs, row) -> new Object[] {rs.getObject(1, UUID.class), rs.getDouble(2), rs.getDouble(3), rs.getInt(4)}, venueId);
        if (zones.isEmpty()) {
            return null;
        }
        if (latitude == null || longitude == null) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "LOCATION_REQUIRED", "Choose the address on the map");
        }
        Point where;
        try {
            where = new Point(latitude, longitude);
        } catch (IllegalArgumentException invalid) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "LOCATION_INVALID", "Invalid coordinates");
        }
        for (Object[] zone : zones) {
            if (Geo.distanceMeters(new Point((Double) zone[1], (Double) zone[2]), where) <= (Integer) zone[3]) {
                return zone[0].toString();
            }
        }
        throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "OUT_OF_ZONE", "The address is outside the service area");
    }

    // ---- public quote

    @Transactional(readOnly = true)
    public Quote quote(UUID offerId, Integer areaSqm, OffsetDateTime startsAt, Double latitude, Double longitude, boolean urgent) {
        var row = db.query("""
                select s.id, s.venue_id, v.timezone, s.price_minor, s.price_per_sqm_minor, s.min_area_sqm, s.max_area_sqm
                from marketplace.home_service_offers o
                join marketplace.booking_services s on s.id = o.service_id
                join marketplace.booking_venues v on v.id = s.venue_id
                where o.id = ? and o.status = 'PUBLISHED' and s.available and v.is_open and v.partner_id = any(?::uuid[])
                """, (rs, i) -> new Object[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getString(3),
                        rs.getLong(4), rs.getLong(5), rs.getObject(6, Integer.class), rs.getObject(7, Integer.class)}, offerId, HomeServicesOffersController.arrayLiteral(partners.approvedPartnerIds()))
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "OFFER_NOT_FOUND", "Offer not found"));
        long perSqm = (Long) row[4];
        if (perSqm > 0) {
            Integer min = (Integer) row[5];
            Integer max = (Integer) row[6];
            if (areaSqm == null || min == null || max == null || areaSqm < min || areaSqm > max) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "AREA_INVALID", "Area is outside the allowed range");
            }
        } else if (areaSqm != null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "AREA_NOT_APPLICABLE", "This service is not priced by area");
        }
        long list = (Long) row[3] + perSqm * (areaSqm == null ? 0 : areaSqm);
        var charges = charges((UUID) row[1], (UUID) row[0], list, startsAt, java.time.ZoneId.of((String) row[2]), latitude, longitude, urgent);
        return new Quote(offerId.toString(), list, charges.callOutFeeMinor(), charges.urgentSurchargeMinor(),
                charges.eveningSurchargeMinor(), list + charges.totalMinor(), "KZT", charges.zoneId());
    }

    // ---- partner writes

    @Transactional(readOnly = true)
    public List<Zone> zones(UUID user, UUID partnerId, int limit, int offset) {
        if (!partners.isActiveStaffOfApprovedPartner(user, partnerId)) {
            throw partnerNotFound();
        }
        return db.query("select " + ZONE_COLUMNS + " from marketplace.home_service_zones z join marketplace.booking_venues v on v.id = z.venue_id "
                + "where v.partner_id = ? order by z.name, z.id limit ? offset ?", HomeServicePricing::zone, partnerId, limit, offset);
    }

    @Transactional
    public Zone createZone(UUID user, UUID partnerId, UUID venueId, String name, double lat, double lng, int radiusM) {
        requireManager(user, partnerId);
        ownVenue(venueId, partnerId);
        UUID id = db.queryForObject("insert into marketplace.home_service_zones (venue_id, name, center_lat, center_lng, radius_m) "
                + "values (?, ?, ?, ?, ?) returning id", UUID.class, venueId, name.strip(), lat, lng, radiusM);
        return zone(id);
    }

    /** Optimistic update: the stored version must equal {@code expectedVersion}. {@code active=false} retires a zone. */
    @Transactional
    public Zone updateZone(UUID user, UUID partnerId, UUID zoneId, String name, double lat, double lng, int radiusM, boolean active,
            long expectedVersion) {
        requireManager(user, partnerId);
        var current = db.query("select z.version from marketplace.home_service_zones z join marketplace.booking_venues v on v.id = z.venue_id "
                + "where z.id = ? and v.partner_id = ? for update of z", (rs, i) -> rs.getLong(1), zoneId, partnerId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ZONE_NOT_FOUND", "Zone not found"));
        if (current != expectedVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The zone changed; reload and retry");
        }
        db.update("update marketplace.home_service_zones set name = ?, center_lat = ?, center_lng = ?, radius_m = ?, active = ?, "
                + "version = version + 1, updated_at = now() where id = ?", name.strip(), lat, lng, radiusM, active, zoneId);
        return zone(zoneId);
    }

    /** Creates the tariff ({@code expectedVersion} 0) or updates it; only for an offer of the partner's own venue. */
    @Transactional
    public Tariff saveTariff(UUID user, UUID partnerId, UUID offerId, long callOutFeeMinor, int urgentPercent, int eveningPercent,
            LocalTime eveningFrom, long expectedVersion) {
        requireManager(user, partnerId);
        boolean owned = Boolean.TRUE.equals(db.queryForObject("""
                select exists (select 1 from marketplace.home_service_offers o
                    join marketplace.booking_services s on s.id = o.service_id
                    join marketplace.booking_venues v on v.id = s.venue_id
                    where o.id = ? and v.partner_id = ?)
                """, Boolean.class, offerId, partnerId));
        if (!owned) {
            throw new ApiException(HttpStatus.NOT_FOUND, "OFFER_NOT_FOUND", "Offer not found");
        }
        // Serialise writers of one tariff: lock the offer row (the tariff row may not exist yet).
        db.queryForObject("select id from marketplace.home_service_offers where id = ? for update", UUID.class, offerId);
        var current = db.query("select version from marketplace.home_service_tariffs where offer_id = ?", (rs, i) -> rs.getLong(1), offerId)
                .stream().findFirst();
        long stored = current.orElse(0L);
        if (stored != expectedVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The tariff changed; reload and retry");
        }
        if (current.isEmpty()) {
            db.update("insert into marketplace.home_service_tariffs (offer_id, call_out_fee_minor, urgent_surcharge_percent, "
                    + "evening_surcharge_percent, evening_from) values (?, ?, ?, ?, ?)", offerId, callOutFeeMinor, urgentPercent,
                    eveningPercent, java.sql.Time.valueOf(eveningFrom));
        } else {
            db.update("update marketplace.home_service_tariffs set call_out_fee_minor = ?, urgent_surcharge_percent = ?, "
                    + "evening_surcharge_percent = ?, evening_from = ?, version = version + 1, updated_at = now() where offer_id = ?",
                    callOutFeeMinor, urgentPercent, eveningPercent, java.sql.Time.valueOf(eveningFrom), offerId);
        }
        return db.queryForObject("select offer_id, call_out_fee_minor, urgent_surcharge_percent, evening_surcharge_percent, evening_from, version "
                + "from marketplace.home_service_tariffs where offer_id = ?", (rs, i) -> new Tariff(rs.getString(1), rs.getLong(2),
                        rs.getInt(3), rs.getInt(4), rs.getTime(5).toLocalTime().toString(), rs.getLong(6)), offerId);
    }

    private void requireManager(UUID user, UUID partnerId) {
        if (partners.lockCatalogManager(user, partnerId)) {
            return;
        }
        if (partners.isActiveStaffOfApprovedPartner(user, partnerId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "PARTNER_ROLE_FORBIDDEN", "Role is not allowed to do this");
        }
        throw partnerNotFound();
    }

    private void ownVenue(UUID venueId, UUID partnerId) {
        boolean owned = Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from marketplace.booking_venues "
                + "where id = ? and partner_id = ? and category = 'CLEANING')", Boolean.class, venueId, partnerId));
        if (!owned) {
            throw new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue not found");
        }
    }

    private static ApiException partnerNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND", "Partner not found");
    }

    private Zone zone(UUID id) {
        return db.queryForObject("select " + ZONE_COLUMNS + " from marketplace.home_service_zones z where z.id = ?",
                HomeServicePricing::zone, id);
    }

    private static Zone zone(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new Zone(rs.getString("id"), rs.getString("venue_id"), rs.getString("name"), rs.getDouble("center_lat"),
                rs.getDouble("center_lng"), rs.getInt("radius_m"), rs.getBoolean("active"), rs.getLong("version"));
    }
}
