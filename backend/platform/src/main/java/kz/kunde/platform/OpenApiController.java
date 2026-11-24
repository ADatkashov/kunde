package kz.kunde.platform;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StreamUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class OpenApiController {
    @GetMapping(value = "/api/v1/openapi.yaml", produces = "application/yaml")
    public ResponseEntity<String> openApi() throws IOException {
        String spec;
        try (InputStream input = new ClassPathResource("openapi/kunde-api-v1.yaml").getInputStream()) {
            spec = StreamUtils.copyToString(input, StandardCharsets.UTF_8);
        }
        return ResponseEntity.ok().contentType(MediaType.parseMediaType("application/yaml")).body(spec);
    }
}
