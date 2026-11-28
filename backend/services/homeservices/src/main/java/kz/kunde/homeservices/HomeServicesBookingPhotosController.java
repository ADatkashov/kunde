package kz.kunde.homeservices;

import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/home-services/bookings/{bookingId}/photos")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.home-services.enabled", "app.home-services.photos.enabled", "app.booking.enabled",
        "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
class HomeServicesBookingPhotosController {
    private final HomeServiceBookingPhotos photos;
    private final FeatureToggles toggles;

    HomeServicesBookingPhotosController(HomeServiceBookingPhotos photos, FeatureToggles toggles) {
        this.photos = photos;
        this.toggles = toggles;
    }

    @PostMapping(consumes = {"image/jpeg", "image/png"})
    ResponseEntity<HomeServiceBookingPhotos.Photo> upload(@AuthenticationPrincipal Jwt principal, @PathVariable UUID bookingId,
            @RequestHeader("Idempotency-Key") UUID idempotencyKey, HttpServletRequest request) throws IOException {
        UUID actor = user(principal);
        photos.requireOwner(actor, bookingId);
        if (request.getContentLengthLong() > HomeServicePhotoNormalizer.MAX_BYTES) {
            throw new ApiException(HttpStatus.CONTENT_TOO_LARGE, "PHOTO_TOO_LARGE", "The photo exceeds the size limit");
        }
        MediaType mediaType = MediaType.parseMediaType(request.getContentType());
        var input = HomeServicePhotoNormalizer.normalize(request.getInputStream(), mediaType.getType() + "/" + mediaType.getSubtype());
        return ok(photos.upload(actor, bookingId, idempotencyKey, input));
    }

    @GetMapping
    ResponseEntity<List<HomeServiceBookingPhotos.Photo>> list(@AuthenticationPrincipal Jwt principal, @PathVariable UUID bookingId) {
        return ok(photos.list(user(principal), bookingId));
    }

    @GetMapping("/{photoId}")
    ResponseEntity<HomeServiceBookingPhotos.ReadUrl> read(@AuthenticationPrincipal Jwt principal, @PathVariable UUID bookingId,
            @PathVariable UUID photoId) {
        return ok(photos.read(user(principal), bookingId, photoId));
    }

    @DeleteMapping("/{photoId}")
    ResponseEntity<Void> delete(@AuthenticationPrincipal Jwt principal, @PathVariable UUID bookingId, @PathVariable UUID photoId) {
        photos.delete(user(principal), bookingId, photoId);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    private UUID user(Jwt principal) {
        if (!toggles.enabled(FeatureToggles.Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
        try {
            return UUID.fromString(principal.getSubject());
        } catch (IllegalArgumentException | NullPointerException invalid) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed");
        }
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
