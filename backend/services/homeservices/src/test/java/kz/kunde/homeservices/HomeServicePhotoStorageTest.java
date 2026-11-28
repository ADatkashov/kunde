package kz.kunde.homeservices;

import java.net.URI;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;
import static org.assertj.core.api.Assertions.assertThatIllegalStateException;
import static org.mockito.Mockito.mock;

class HomeServicePhotoStorageTest {
    @Test
    void signsOnlyPrivatePhotoKeysForThreeMinutes() {
        var credentials = StaticCredentialsProvider.create(AwsBasicCredentials.create("test-access", "test-secret"));
        var config = S3Configuration.builder().pathStyleAccessEnabled(true).build();
        var presigner = S3Presigner.builder().region(Region.of("auto")).credentialsProvider(credentials)
                .endpointOverride(URI.create("https://storage.example.test")).serviceConfiguration(config).build();
        try (var storage = new HomeServicePhotoStorage(mock(S3Client.class), presigner, "private-photos")) {
            String key = HomeServicePhotoStorage.key(UUID.randomUUID(), "image/jpeg");
            URI signed = storage.signedRead(key);
            assertThat(signed.getPath()).isEqualTo("/private-photos/" + key);
            assertThat(signed.getRawQuery()).contains("X-Amz-Expires=180", "X-Amz-Signature=");
            assertThatIllegalArgumentException().isThrownBy(() -> storage.signedRead("../private-file.jpeg"));
        }
    }

    @Test
    void cleartextIsOnlyAllowedForLoopback() {
        HomeServicePhotoStorageConfiguration.validateEndpoint(URI.create("http://127.0.0.1:9000"));
        HomeServicePhotoStorageConfiguration.validateEndpoint(URI.create("https://storage.example.test"));
        assertThatIllegalStateException().isThrownBy(
                () -> HomeServicePhotoStorageConfiguration.validateEndpoint(URI.create("http://storage.example.test")));
        assertThatIllegalStateException().isThrownBy(
                () -> HomeServicePhotoStorageConfiguration.validateEndpoint(URI.create("https://storage.example.test/folder")));
    }
}
