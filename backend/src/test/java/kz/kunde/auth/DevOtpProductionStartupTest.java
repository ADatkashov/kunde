package kz.kunde.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import kz.kunde.KundeApplication;
import org.junit.jupiter.api.Test;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;

/** The real application context must refuse to start with DEV OTP outside dev/local/test. */
class DevOtpProductionStartupTest {
    private static Throwable root(Throwable t) {
        while (t.getCause() != null) t = t.getCause();
        return t;
    }

    @Test
    void applicationRefusesToStartWithDevOtpInProduction() {
        assertThatThrownBy(() -> new SpringApplicationBuilder(KundeApplication.class)
                .web(WebApplicationType.SERVLET)
                .run("--server.port=0", "--app.environment=production", "--app.auth.phone.enabled=true",
                        "--app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
                        "--app.auth.phone.dev-otp.enabled=true",
                        "--app.auth.phone.dev-otp.allowed-phones=+77000000001"))
                .satisfies(failure -> assertThat(root(failure)).isInstanceOf(IllegalStateException.class)
                        .hasMessageContaining("DEV OTP is forbidden"));
    }
}
