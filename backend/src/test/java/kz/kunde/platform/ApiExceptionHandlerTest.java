package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockHttpServletRequest;

class ApiExceptionHandlerTest {
    @Test
    void returnsStableSafeErrorShape() {
        var request = new MockHttpServletRequest("POST", "/api/v1/assistant/messages");
        var result = new ApiExceptionHandler().handleApiException(
                new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "FEATURE_UNAVAILABLE", "Feature is disabled"), request);

        assertThat(result.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(result.getBody()).isNotNull();
        assertThat(result.getBody().code()).isEqualTo("FEATURE_UNAVAILABLE");
        assertThat(result.getBody().path()).isEqualTo("/api/v1/assistant/messages");
        assertThat(result.getBody().correlationId()).isEqualTo("unavailable");
    }
}
