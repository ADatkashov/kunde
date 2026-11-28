package kz.kunde.homeservices;

import java.net.URI;
import java.time.Duration;
import java.util.UUID;
import java.util.regex.Pattern;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

/** Private bucket access. The caller establishes role and subject access before asking for a read URL. */
final class HomeServicePhotoStorage implements AutoCloseable {
    private static final Pattern KEY = Pattern.compile("home-services/photos/[0-9a-f-]{36}\\.(jpeg|png)");
    static final int READ_TTL_SECONDS = 180;
    private static final Duration READ_TTL = Duration.ofSeconds(READ_TTL_SECONDS);

    private final S3Client objects;
    private final S3Presigner presigner;
    private final String bucket;

    HomeServicePhotoStorage(S3Client objects, S3Presigner presigner, String bucket) {
        this.objects = objects;
        this.presigner = presigner;
        this.bucket = bucket;
    }

    static String key(UUID photo, String contentType) {
        String extension = switch (contentType) {
            case "image/jpeg" -> "jpeg";
            case "image/png" -> "png";
            default -> throw new IllegalArgumentException("Invalid normalized photo content type");
        };
        return "home-services/photos/" + photo + "." + extension;
    }

    /** Resume a committed reservation after an upload whose result may have been lost. */
    void putReserved(String key, HomeServicePhotoNormalizer.Photo photo) {
        validateKey(key);
        try {
            objects.putObject(request -> request.bucket(bucket).key(key).contentType(photo.contentType())
                    .cacheControl("private, no-store").ifNoneMatch("*"), RequestBody.fromBytes(photo.bytes()));
        } catch (S3Exception failure) {
            if (failure.statusCode() != 412) {
                throw storageUnavailable();
            }
        } catch (SdkException unavailable) {
            throw storageUnavailable();
        }
    }

    URI signedRead(String key) {
        validateKey(key);
        var object = GetObjectRequest.builder().bucket(bucket).key(key).build();
        try {
            return URI.create(presigner.presignGetObject(request -> request
                    .signatureDuration(READ_TTL).getObjectRequest(object)).url().toExternalForm());
        } catch (SdkException unavailable) {
            throw storageUnavailable();
        }
    }

    void delete(String key) {
        validateKey(key);
        try {
            objects.deleteObject(request -> request.bucket(bucket).key(key));
        } catch (SdkException unavailable) {
            throw storageUnavailable();
        }
    }

    private static void validateKey(String key) {
        if (!KEY.matcher(key).matches()) {
            throw new IllegalArgumentException("Invalid photo object key");
        }
    }

    private static ApiException storageUnavailable() {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "PHOTO_STORAGE_UNAVAILABLE", "Photo storage is unavailable");
    }

    @Override
    public void close() {
        try {
            objects.close();
        } finally {
            presigner.close();
        }
    }
}
