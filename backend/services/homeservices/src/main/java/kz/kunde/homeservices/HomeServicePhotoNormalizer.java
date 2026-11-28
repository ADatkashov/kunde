package kz.kunde.homeservices;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Locale;
import javax.imageio.ImageIO;
import javax.imageio.stream.MemoryCacheImageInputStream;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;

/** Produces JPEG or PNG from decoded pixels so uploaded metadata never reaches storage. */
final class HomeServicePhotoNormalizer {
    static final int MAX_BYTES = 8 * 1024 * 1024;
    static final long MAX_PIXELS = 12_000_000;
    static final int MAX_DIMENSION = 6_000;

    record Photo(byte[] bytes, String contentType, int width, int height) {}

    private HomeServicePhotoNormalizer() {}

    static Photo normalize(InputStream input, String contentType) throws IOException {
        String format = switch (contentType == null ? "" : contentType.toLowerCase(Locale.ROOT)) {
            case "image/jpeg" -> "jpeg";
            case "image/png" -> "png";
            default -> throw unsupported();
        };
        byte[] bytes = input.readNBytes(MAX_BYTES + 1);
        if (bytes.length > MAX_BYTES) {
            throw tooLarge();
        }
        BufferedImage pixels;
        try (var stream = new MemoryCacheImageInputStream(new ByteArrayInputStream(bytes))) {
            var readers = ImageIO.getImageReaders(stream);
            if (!readers.hasNext()) {
                throw unsupported();
            }
            var reader = readers.next();
            try {
                if (!format.equalsIgnoreCase(reader.getFormatName())) {
                    throw unsupported();
                }
                reader.setInput(stream, true, true);
                int width = reader.getWidth(0);
                int height = reader.getHeight(0);
                if (width < 1 || height < 1 || width > MAX_DIMENSION || height > MAX_DIMENSION
                        || (long) width * height > MAX_PIXELS) {
                    throw tooLarge();
                }
                pixels = reader.read(0);
            } finally {
                reader.dispose();
            }
        } catch (IOException | IllegalArgumentException invalid) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_CONTENT, "PHOTO_INVALID", "The photo could not be decoded");
        }

        try (var output = new ByteArrayOutputStream()) {
            if (!ImageIO.write(pixels, format, output)) {
                throw unsupported();
            }
            if (output.size() > MAX_BYTES) {
                throw tooLarge();
            }
            return new Photo(output.toByteArray(), "image/" + format, pixels.getWidth(), pixels.getHeight());
        }
    }

    private static ApiException unsupported() {
        return new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "PHOTO_FORMAT_INVALID", "Upload a JPEG or PNG photo");
    }

    private static ApiException tooLarge() {
        return new ApiException(HttpStatus.CONTENT_TOO_LARGE, "PHOTO_TOO_LARGE", "The photo exceeds the size limit");
    }
}
