package kz.kunde.homeservices;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import javax.imageio.ImageIO;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class HomeServicePhotoNormalizerTest {
    @Test
    void reencodesJpegWithoutAppMetadata() throws Exception {
        byte[] jpeg = image("jpeg", 32, 24);
        byte[] exif = "Exif\0\0Synthetic GPS".getBytes(StandardCharsets.US_ASCII);
        var uploaded = new ByteArrayOutputStream();
        uploaded.write(jpeg, 0, 2);
        uploaded.write(new byte[] {(byte) 0xff, (byte) 0xe1, 0, (byte) (exif.length + 2)});
        uploaded.write(exif);
        uploaded.write(jpeg, 2, jpeg.length - 2);

        var clean = HomeServicePhotoNormalizer.normalize(new ByteArrayInputStream(uploaded.toByteArray()), "image/jpeg");
        assertThat(clean.contentType()).isEqualTo("image/jpeg");
        assertThat(clean.width()).isEqualTo(32);
        assertThat(clean.height()).isEqualTo(24);
        assertThat(new String(clean.bytes(), StandardCharsets.ISO_8859_1)).doesNotContain("Synthetic GPS");
        assertThat(ImageIO.read(new ByteArrayInputStream(clean.bytes())).getWidth()).isEqualTo(32);
    }

    @Test
    void refusesSpoofedFormatAndOversizedPayload() throws Exception {
        byte[] png = image("png", 4, 4);
        assertThatThrownBy(() -> HomeServicePhotoNormalizer.normalize(new ByteArrayInputStream(png), "image/jpeg"))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.status().value()).isEqualTo(415));
        byte[] large = Arrays.copyOf(png, HomeServicePhotoNormalizer.MAX_BYTES + 1);
        assertThatThrownBy(() -> HomeServicePhotoNormalizer.normalize(new ByteArrayInputStream(large), "image/png"))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.status().value()).isEqualTo(413));
    }

    @Test
    void refusesDimensionsBeforeDecodingPixels() throws Exception {
        byte[] wide = image("png", HomeServicePhotoNormalizer.MAX_DIMENSION + 1, 1);
        assertThatThrownBy(() -> HomeServicePhotoNormalizer.normalize(new ByteArrayInputStream(wide), "image/png"))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.status().value()).isEqualTo(413));
    }

    private static byte[] image(String format, int width, int height) throws Exception {
        var output = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), format, output);
        return output.toByteArray();
    }
}
