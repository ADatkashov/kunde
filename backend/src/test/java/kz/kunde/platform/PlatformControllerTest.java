package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class PlatformControllerTest {
    @Test
    void reportsOnlyCapabilitiesThatAreActuallyAvailable() {
        var capabilities = new PlatformController("", "").capabilities();

        assertThat(capabilities.releaseStage()).isEqualTo("FOUNDATION");
        assertThat(capabilities.marketplaceEnabled()).isFalse();
        assertThat(capabilities.oidcIssuerConfigured()).isFalse();
        assertThat(capabilities.aiEnabled()).isFalse();
    }

    @Test
    void doesNotReportOidcConfiguredUntilIssuerAndAudienceArePresent() {
        var capabilities = new PlatformController("https://identity.example.test", "kunde-api").capabilities();

        assertThat(capabilities.oidcIssuerConfigured()).isTrue();
        assertThat(capabilities.marketplaceEnabled()).isFalse();
        assertThat(capabilities.aiEnabled()).isFalse();
    }
}
