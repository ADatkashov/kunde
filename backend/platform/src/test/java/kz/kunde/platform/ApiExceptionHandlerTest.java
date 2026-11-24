package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockHttpServletRequest;

class ApiExceptionHandlerTest {
    @Test
    void pocExceptionsNeverLogSensitiveMessagesOrStackTraces() {
        var logger = (ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(ApiExceptionHandler.class);
        var appender = new ch.qos.logback.core.read.ListAppender<ch.qos.logback.classic.spi.ILoggingEvent>();
        appender.start();
        logger.addAppender(appender);
        try {
            var request = new MockHttpServletRequest("GET", "/api/v1/poc/whoami");
            var result = new ApiExceptionHandler().handleUnexpected(
                    new IllegalStateException("sensitive-sentinel-value"), request);
            assertThat(result.getBody().message()).isEqualTo("The request could not be completed");
            assertThat(appender.list).hasSize(1);
            assertThat(appender.list.getFirst().getFormattedMessage()).doesNotContain("sensitive-sentinel-value");
            assertThat(appender.list.getFirst().getThrowableProxy()).isNull();
        } finally {
            logger.detachAppender(appender);
            appender.stop();
        }
    }

    @Test
    void methodAuthorizationDenialReturnsSafeForbiddenResponse() {
        var request = new MockHttpServletRequest("GET", "/api/v1/me");
        var result = new ApiExceptionHandler().handleAccessDenied(
                new org.springframework.security.access.AccessDeniedException("sensitive-policy-details"), request);
        assertThat(result.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(result.getBody().code()).isEqualTo("FORBIDDEN");
        assertThat(result.getBody().message()).isEqualTo("Access is denied");
        assertThat(result.getBody().correlationId()).isEqualTo("unavailable");
    }

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
