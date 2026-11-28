package kz.kunde.homeservices;

import java.net.URI;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.booking.BookingService;
import kz.kunde.booking.BookingService.HomePhotoScope;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
@ConditionalOnProperty(name = {"app.home-services.enabled", "app.home-services.photos.enabled", "app.booking.enabled"}, havingValue = "true")
class HomeServiceBookingPhotos {
    private static final int MAX_PROBLEM_PHOTOS = 6;
    private static final int CLEANUP_BATCH_SIZE = 20;
    private static final String SCOPED = """
            subject_type = 'BOOKING' and subject_id = ? and venue_id = ?
            and city_id is not distinct from ?::uuid and partner_id is not distinct from ?::uuid
            """;

    record Photo(UUID id, String purpose, String contentType, int byteSize, int width, int height, OffsetDateTime createdAt) {}
    record ReadUrl(URI url, int expiresInSeconds) {}
    private record Reservation(UUID id, String state, byte[] hash) {}
    private record StoredObject(UUID id, String contentType) {}

    private final JdbcTemplate db;
    private final BookingService bookings;
    private final HomeServicePhotoStorage storage;
    private final TransactionTemplate transactions;

    HomeServiceBookingPhotos(JdbcTemplate db, BookingService bookings, HomeServicePhotoStorage storage,
            PlatformTransactionManager transactionManager) {
        this.db = db;
        this.bookings = bookings;
        this.storage = storage;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    void requireOwner(UUID actor, UUID booking) {
        transactions.executeWithoutResult(transaction -> bookings.lockHomeBookingForCustomerPhotos(actor, booking));
    }

    Photo upload(UUID actor, UUID booking, UUID idempotencyKey, HomeServicePhotoNormalizer.Photo input) {
        byte[] hash = sha256(input.bytes());
        UUID id = transactions.execute(transaction -> {
            HomePhotoScope scope = bookings.lockHomeBookingForCustomerPhotos(actor, booking);
            var previous = db.query("select id, state, content_sha256 from marketplace.home_service_photos where "
                            + SCOPED + " and uploaded_by = ? and idempotency_key = ?",
                    (rs, n) -> new Reservation(rs.getObject(1, UUID.class), rs.getString(2), rs.getBytes(3)),
                    booking, scope.venueId(), scope.cityId(), scope.partnerId(), actor, idempotencyKey).stream().findFirst();
            if (previous.isPresent()) {
                Reservation reservation = previous.get();
                if (!MessageDigest.isEqual(hash, reservation.hash()) || "DELETED".equals(reservation.state())) {
                    throw new ApiException(HttpStatus.CONFLICT, "PHOTO_IDEMPOTENCY_CONFLICT", "Use a new key for a different upload");
                }
                return reservation.id();
            }
            requireEditable(scope);
            int count = db.queryForObject("select count(*) from marketplace.home_service_photos where " + SCOPED
                            + " and purpose = 'PROBLEM' and state in ('PENDING', 'READY')",
                    Integer.class, booking, scope.venueId(), scope.cityId(), scope.partnerId());
            if (count >= MAX_PROBLEM_PHOTOS) {
                throw new ApiException(HttpStatus.CONFLICT, "PHOTO_LIMIT_REACHED", "Too many photos for this order");
            }
            UUID photoId = UUID.randomUUID();
            db.update("""
                    insert into marketplace.home_service_photos
                        (id, subject_type, subject_id, venue_id, city_id, partner_id, uploaded_by, purpose,
                         idempotency_key, content_sha256, content_type, byte_size, width, height, moderation)
                    values (?, 'BOOKING', ?, ?, ?, ?, ?, 'PROBLEM', ?, ?, ?, ?, ?, ?, 'PRIVATE')
                    """, photoId, booking, scope.venueId(), scope.cityId(), scope.partnerId(), actor, idempotencyKey,
                    hash, input.contentType(), input.bytes().length, input.width(), input.height());
            return photoId;
        });

        return transactions.execute(transaction -> {
            HomePhotoScope scope = bookings.lockHomeBookingForCustomerPhotos(actor, booking);
            String state = db.query("select state from marketplace.home_service_photos where " + SCOPED + " and id = ? for update",
                    (rs, n) -> rs.getString(1), booking, scope.venueId(), scope.cityId(), scope.partnerId(), id)
                    .stream().findFirst().orElseThrow(HomeServiceBookingPhotos::notFound);
            if ("PENDING".equals(state)) {
                requireEditable(scope);
                storage.putReserved(HomeServicePhotoStorage.key(id, input.contentType()), input);
                db.update("update marketplace.home_service_photos set state = 'READY', updated_at = now() where id = ?", id);
                audit(id, actor, "UPLOAD");
            }
            return readyPhotos(booking, scope, id).stream().findFirst().orElseThrow(HomeServiceBookingPhotos::notFound);
        });
    }

    List<Photo> list(UUID actor, UUID booking) {
        return transactions.execute(transaction -> readyPhotos(booking, bookings.lockHomeBookingForCustomerPhotos(actor, booking), null));
    }

    ReadUrl read(UUID actor, UUID booking, UUID id) {
        return transactions.execute(transaction -> {
            var photo = readyPhotos(booking, bookings.lockHomeBookingForCustomerPhotos(actor, booking), id).stream().findFirst()
                    .orElseThrow(HomeServiceBookingPhotos::notFound);
            return new ReadUrl(storage.signedRead(HomeServicePhotoStorage.key(id, photo.contentType())),
                    HomeServicePhotoStorage.READ_TTL_SECONDS);
        });
    }

    void delete(UUID actor, UUID booking, UUID id) {
        transactions.executeWithoutResult(transaction -> {
            HomePhotoScope scope = bookings.lockHomeBookingForCustomerPhotos(actor, booking);
            requireEditable(scope);
            int updated = db.update("""
                    update marketplace.home_service_photos set state = 'DELETED', updated_at = now()
                    where
                    """ + SCOPED + " and id = ? and uploaded_by = ? and purpose = 'PROBLEM' and state <> 'DELETED'",
                    booking, scope.venueId(), scope.cityId(), scope.partnerId(), id, actor);
            if (updated != 0) {
                audit(id, actor, "DELETE");
            }
        });
    }

    @Scheduled(fixedDelay = 60000)
    void removeUnusedObjects() {
        for (int index = 0; index < CLEANUP_BATCH_SIZE; index++) {
            if (!Boolean.TRUE.equals(transactions.execute(transaction -> removeNextUnusedObject()))) {
                break;
            }
        }
    }

    private boolean removeNextUnusedObject() {
        var rows = db.query("""
                select id, content_type from marketplace.home_service_photos
                where object_removed_at is null
                  and (state = 'DELETED' or (state = 'PENDING' and updated_at < now() - interval '1 day'))
                order by updated_at, id limit 1 for update skip locked
                """, (rs, n) -> new StoredObject(rs.getObject(1, UUID.class), rs.getString(2)));
        if (rows.isEmpty()) {
            return false;
        }
        StoredObject object = rows.getFirst();
        storage.delete(HomeServicePhotoStorage.key(object.id(), object.contentType()));
        db.update("""
                update marketplace.home_service_photos set state = 'DELETED', object_removed_at = now(), updated_at = now()
                where id = ?
                """, object.id());
        return true;
    }

    private List<Photo> readyPhotos(UUID booking, HomePhotoScope scope, UUID id) {
        return db.query("""
                select id, purpose, content_type, byte_size, width, height, created_at
                from marketplace.home_service_photos where
                """ + SCOPED + " and state = 'READY' and (?::uuid is null or id = ?) order by created_at, id",
                (rs, n) -> new Photo(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), rs.getInt(4),
                        rs.getInt(5), rs.getInt(6), rs.getObject(7, OffsetDateTime.class)),
                booking, scope.venueId(), scope.cityId(), scope.partnerId(), id, id);
    }

    private void audit(UUID photo, UUID actor, String action) {
        db.update("insert into marketplace.home_service_photo_events (photo_id, actor_id, action) values (?, ?, ?)", photo, actor, action);
    }

    private static void requireEditable(HomePhotoScope scope) {
        if (!"PENDING".equals(scope.status()) && !"CONFIRMED".equals(scope.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_PHOTOS_LOCKED", "Problem photos can only change before work starts");
        }
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "PHOTO_NOT_FOUND", "Photo not found");
    }

    private static byte[] sha256(byte[] bytes) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(bytes);
        } catch (NoSuchAlgorithmException unavailable) {
            throw new IllegalStateException("SHA-256 is required", unavailable);
        }
    }
}
