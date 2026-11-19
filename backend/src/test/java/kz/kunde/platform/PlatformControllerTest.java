package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import kz.kunde.delivery.DeliveryProperties;
import kz.kunde.rides.RidesFlags;
import org.junit.jupiter.api.Test;

class PlatformControllerTest {
    @Test
    void reportsOnlyCapabilitiesThatAreActuallyAvailable() {
        var capabilities = new PlatformController("", "", false, false,
                new RidesFlags(false, false, false, false, false, false), mock(DeliveryProperties.class)).capabilities();

        assertThat(capabilities.deliveryEnabled()).isFalse();
        assertThat(capabilities.releaseStage()).isEqualTo("FOUNDATION");
        assertThat(capabilities.marketplaceEnabled()).isFalse();
        assertThat(capabilities.oidcIssuerConfigured()).isFalse();
        assertThat(capabilities.aiEnabled()).isFalse();
    }

    @Test
    void doesNotReportOidcConfiguredUntilIssuerAndAudienceArePresent() {
        var capabilities = new PlatformController("https://identity.example.test", "kunde-api", false, false,
                new RidesFlags(false, false, false, false, false, false), mock(DeliveryProperties.class)).capabilities();

        assertThat(capabilities.oidcIssuerConfigured()).isTrue();
        assertThat(capabilities.marketplaceEnabled()).isFalse();
        assertThat(capabilities.aiEnabled()).isFalse();
    }
}
