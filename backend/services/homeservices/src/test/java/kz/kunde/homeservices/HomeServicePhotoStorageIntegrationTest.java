package kz.kunde.homeservices;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

@EnabledIfEnvironmentVariable(named = "HOME_SERVICES_TEST_S3_ENDPOINT", matches = ".+")
class HomeServicePhotoStorageIntegrationTest {
    @Test
    void privateObjectIsReadableOnlyWithSignatureAndDisappearsAfterDeletion() throws Exception {
        URI endpoint = URI.create(System.getenv("HOME_SERVICES_TEST_S3_ENDPOINT"));
        HomeServicePhotoStorageConfiguration.validateEndpoint(endpoint);
        assertThat(endpoint.getHost()).isIn("127.0.0.1", "localhost");
        var credentials = StaticCredentialsProvider.create(AwsBasicCredentials.create(
                System.getenv("HOME_SERVICES_TEST_S3_ACCESS_KEY"), System.getenv("HOME_SERVICES_TEST_S3_SECRET_KEY")));
        Region region = Region.US_EAST_1;
        var configuration = S3Configuration.builder().pathStyleAccessEnabled(true).build();
        String bucket = "h11-test-" + UUID.randomUUID();
        try (var setup = S3Client.builder().endpointOverride(endpoint).region(region)
                .serviceConfiguration(configuration).credentialsProvider(credentials).build();
             var storage = new HomeServicePhotoStorage(
                     S3Client.builder().endpointOverride(endpoint).region(region).serviceConfiguration(configuration).credentialsProvider(credentials).build(),
                     S3Presigner.builder().endpointOverride(endpoint).region(region).serviceConfiguration(configuration).credentialsProvider(credentials).build(),
                     bucket)) {
            setup.createBucket(request -> request.bucket(bucket));
            var image = new ByteArrayOutputStream();
            ImageIO.write(new BufferedImage(2, 3, BufferedImage.TYPE_INT_RGB), "png", image);
            var photo = HomeServicePhotoNormalizer.normalize(new ByteArrayInputStream(image.toByteArray()), "image/png");
            String key = HomeServicePhotoStorage.key(UUID.randomUUID(), photo.contentType());

            try (var http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build()) {
                storage.putReserved(key, photo);
                storage.putReserved(key, photo);
                URI signed = storage.signedRead(key);
                URI unsigned = signed.resolve(signed.getRawPath());
                assertThat(read(http, unsigned).statusCode()).isEqualTo(403);
                var response = read(http, signed);
                assertThat(response.statusCode()).isEqualTo(200);
                assertThat(response.headers().firstValue("Content-Type")).contains("image/png");
                assertThat(response.headers().firstValue("Cache-Control")).contains("private, no-store");
                assertThat(response.body()).isEqualTo(photo.bytes());

                storage.delete(key);
                storage.delete(key);
                assertThatExceptionOfType(S3Exception.class)
                        .isThrownBy(() -> setup.headObject(request -> request.bucket(bucket).key(key)))
                        .satisfies(error -> assertThat(error.statusCode()).isEqualTo(404));
            } finally {
                try {
                    storage.delete(key);
                } finally {
                    setup.deleteBucket(request -> request.bucket(bucket));
                }
            }
        }
    }

    private static HttpResponse<byte[]> read(HttpClient client, URI uri) throws Exception {
        return client.send(HttpRequest.newBuilder(uri).timeout(Duration.ofSeconds(10)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
    }
}
