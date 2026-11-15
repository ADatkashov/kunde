package kz.kunde.partner;

import java.util.List;
import java.util.UUID;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * ADR-018 step 3: a partner's own offerings. Every method first proves the caller is active staff of the path
 * partner ({@link PartnerService#requireRole}, 404 for strangers) and then only touches rows with that
 * {@code partner_id}, so another partner's offering is indistinguishable from an unknown id (IDOR guard).
 * OWNER/MANAGER write, every active role reads. Publishing needs an APPROVED partner and a price (D-04: one final
 * KZT price in tiyn, no fees); consumers still only see PUBLISHED offerings of APPROVED partners in PUBLISHED
 * categories (ADR-014), so nothing here makes the catalog orderable by itself.
 */
@Service
public class PartnerOfferingService {
    static final int MAX_OFFERINGS_PER_PARTNER = 500;
    /** 10 million KZT in tiyn: a sanity bound, not a pricing rule. */
    static final long MAX_PRICE_MINOR = 1_000_000_000L;

    public record OfferingView(UUID id, UUID partnerId, UUID categoryId, String kind, String nameRu, String nameKk,
            String nameEn, String status, Long priceMinor, String currency, String availability, long version) { }

    /** Writable fields; category and kind are fixed at creation. */
    public record OfferingInput(UUID categoryId, String kind, String nameRu, String nameKk, String nameEn,
            Long priceMinor, String availability) { }

    /** A category a partner may attach an offering to; DRAFT categories are listed too (offerings stay DRAFT until ADR-014 gates open). */
    public record CategoryOption(UUID id, String code, String nameRu, String nameKk, String nameEn, String status) { }

    private static final RowMapper<OfferingView> VIEW = (rs, i) -> new OfferingView(
            rs.getObject("id", UUID.class), rs.getObject("partner_id", UUID.class), rs.getObject("category_id", UUID.class),
            rs.getString("kind"), rs.getString("name_ru"), rs.getString("name_kk"), rs.getString("name_en"),
            rs.getString("status"), rs.getObject("price_minor", Long.class), rs.getString("currency"),
            rs.getString("availability"), rs.getLong("version"));

    private static final String SELECT = """
            SELECT id, partner_id, category_id, kind, name_ru, name_kk, name_en, status, price_minor, currency,
                   availability, version FROM marketplace.offerings""";

    private final JdbcTemplate db;
    private final PartnerService partners;

    public PartnerOfferingService(JdbcTemplate db, PartnerService partners) {
        this.db = db;
        this.partners = partners;
    }

    /** Non-retired categories for the offering form; reference data, no partner data involved. */
    @Transactional(readOnly = true)
    public List<CategoryOption> categories() {
        return db.query("""
                SELECT id, code, name_ru, name_kk, name_en, status FROM marketplace.categories
                WHERE status <> 'RETIRED' ORDER BY sort_order, code""",
                (rs, i) -> new CategoryOption(rs.getObject("id", UUID.class), rs.getString("code"), rs.getString("name_ru"),
                        rs.getString("name_kk"), rs.getString("name_en"), rs.getString("status")));
    }

    @Transactional
    public OfferingView create(UUID actor, UUID partnerId, OfferingInput in) {
        partners.requireRole(partnerId, actor, Role.OWNER, Role.MANAGER);
        validate(in, true);
        db.queryForList("SELECT 1 FROM marketplace.partners WHERE id = ? FOR UPDATE", partnerId);
        Integer existing = db.queryForObject("SELECT count(*) FROM marketplace.offerings WHERE partner_id = ?", Integer.class, partnerId);
        if (existing != null && existing >= MAX_OFFERINGS_PER_PARTNER) {
            throw new ApiException(HttpStatus.CONFLICT, "OFFERING_LIMIT", "Too many offerings for this partner");
        }
        boolean category = db.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM marketplace.categories WHERE id = ? AND status <> 'RETIRED')",
                Boolean.class, in.categoryId());
        if (!category) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_CATEGORY", "Category does not exist or is retired");
        }
        UUID id = db.queryForObject("""
                INSERT INTO marketplace.offerings (category_id, kind, name_ru, name_kk, name_en, partner_id, price_minor, availability)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING id""", UUID.class, in.categoryId(), in.kind(), in.nameRu().strip(),
                in.nameKk().strip(), blankToNull(in.nameEn()), partnerId, in.priceMinor(),
                in.availability() == null ? "UNAVAILABLE" : in.availability());
        event(id, partnerId, actor, "CREATED");
        return load(partnerId, id);
    }

    @Transactional(readOnly = true)
    public List<OfferingView> list(UUID actor, UUID partnerId) {
        partners.requireRole(partnerId, actor, Role.OWNER, Role.MANAGER, Role.OPERATOR);
        return db.query(SELECT + " WHERE partner_id = ? ORDER BY created_at, id", VIEW, partnerId);
    }

    @Transactional(readOnly = true)
    public OfferingView get(UUID actor, UUID partnerId, UUID offeringId) {
        partners.requireRole(partnerId, actor, Role.OWNER, Role.MANAGER, Role.OPERATOR);
        return load(partnerId, offeringId);
    }

    @Transactional
    public OfferingView update(UUID actor, UUID partnerId, UUID offeringId, OfferingInput in, long expectedVersion) {
        partners.requireRole(partnerId, actor, Role.OWNER, Role.MANAGER);
        validate(in, false);
        var current = lockAndLoad(partnerId, offeringId, expectedVersion);
        if ("PUBLISHED".equals(current.status()) && in.priceMinor() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PRICE_REQUIRED", "A published offering needs a price");
        }
        db.update("""
                UPDATE marketplace.offerings SET name_ru = ?, name_kk = ?, name_en = ?, price_minor = ?, availability = ?,
                    version = version + 1, updated_at = now() WHERE id = ? AND partner_id = ?""", in.nameRu().strip(),
                in.nameKk().strip(), blankToNull(in.nameEn()), in.priceMinor(),
                in.availability() == null ? current.availability() : in.availability(), offeringId, partnerId);
        event(offeringId, partnerId, actor, "UPDATED");
        return load(partnerId, offeringId);
    }

    /** DRAFT to PUBLISHED: needs an APPROVED partner, a price and (by DB check) a partner link. */
    @Transactional
    public OfferingView publish(UUID actor, UUID partnerId, UUID offeringId, long expectedVersion) {
        partners.requireRole(partnerId, actor, Role.OWNER, Role.MANAGER);
        var current = lockAndLoad(partnerId, offeringId, expectedVersion);
        if ("PUBLISHED".equals(current.status())) {
            return current;
        }
        if (!"DRAFT".equals(current.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "INVALID_OFFERING_STATE", "Only a draft offering can be published");
        }
        if (!partners.eligibleForCatalogGate(partnerId)) {
            throw new ApiException(HttpStatus.CONFLICT, "PARTNER_NOT_APPROVED", "Publishing needs an approved partner");
        }
        if (current.priceMinor() == null) {
            throw new ApiException(HttpStatus.CONFLICT, "PRICE_REQUIRED", "Set a price before publishing");
        }
        db.update("""
                UPDATE marketplace.offerings SET status = 'PUBLISHED', published_at = now(), version = version + 1,
                    updated_at = now() WHERE id = ? AND partner_id = ?""", offeringId, partnerId);
        event(offeringId, partnerId, actor, "PUBLISHED");
        return load(partnerId, offeringId);
    }

    /** PUBLISHED back to DRAFT; the offering disappears from the consumer catalog immediately. */
    @Transactional
    public OfferingView unpublish(UUID actor, UUID partnerId, UUID offeringId, long expectedVersion) {
        partners.requireRole(partnerId, actor, Role.OWNER, Role.MANAGER);
        var current = lockAndLoad(partnerId, offeringId, expectedVersion);
        if ("DRAFT".equals(current.status())) {
            return current;
        }
        if (!"PUBLISHED".equals(current.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "INVALID_OFFERING_STATE", "Only a published offering can be withdrawn");
        }
        db.update("UPDATE marketplace.offerings SET status = 'DRAFT', version = version + 1, updated_at = now() WHERE id = ? AND partner_id = ?",
                offeringId, partnerId);
        event(offeringId, partnerId, actor, "UNPUBLISHED");
        return load(partnerId, offeringId);
    }

    private OfferingView load(UUID partnerId, UUID offeringId) {
        return db.query(SELECT + " WHERE id = ? AND partner_id = ?", VIEW, offeringId, partnerId).stream().findFirst()
                .orElseThrow(PartnerOfferingService::notFound);
    }

    private OfferingView lockAndLoad(UUID partnerId, UUID offeringId, long expectedVersion) {
        db.queryForList("SELECT 1 FROM marketplace.offerings WHERE id = ? AND partner_id = ? FOR UPDATE", offeringId, partnerId);
        var current = load(partnerId, offeringId);
        if (current.version() != expectedVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "Offering changed; refresh and retry");
        }
        return current;
    }

    private void event(UUID offeringId, UUID partnerId, UUID actor, String type) {
        db.update("INSERT INTO marketplace.offering_events (offering_id, partner_id, actor_user_id, event_type) VALUES (?, ?, ?, ?)",
                offeringId, partnerId, actor, type);
    }

    private static void validate(OfferingInput in, boolean creating) {
        if (creating && (in.categoryId() == null || !List.of("SERVICE", "PRODUCT").contains(in.kind()))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_OFFERING", "Category and kind (SERVICE or PRODUCT) are required");
        }
        if (!validName(in.nameRu(), true) || !validName(in.nameKk(), true) || !validName(in.nameEn(), false)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_OFFERING_NAME", "RU and KK names (1-200) are required; EN is optional");
        }
        if (in.priceMinor() != null && (in.priceMinor() < 0 || in.priceMinor() > MAX_PRICE_MINOR)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PRICE", "Price must be 0..10 000 000 KZT in tiyn");
        }
        if (in.availability() != null && !List.of("AVAILABLE", "UNAVAILABLE").contains(in.availability())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_AVAILABILITY", "Availability must be AVAILABLE or UNAVAILABLE");
        }
    }

    private static boolean validName(String value, boolean required) {
        if (value == null || value.isBlank()) return !required;
        return value.strip().length() <= 200;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "OFFERING_NOT_FOUND", "Offering not found");
    }
}
