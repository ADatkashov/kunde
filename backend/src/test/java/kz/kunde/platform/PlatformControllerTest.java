package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import kz.kunde.rides.RidesFlags;
import org.junit.jupiter.api.Test;

class PlatformControllerTest {
    @Test
    void reportsOnlyCapabilitiesThatAreActuallyAvailable() {
        var capabilities = new PlatformController("", "", false, false,
                TestToggles.of(new RidesFlags(false, false, false, false, false, false))).capabilities();

        assertThat(capabilities.deliveryEnabled()).isFalse();
        assertThat(capabilities.releaseStage()).isEqualTo("FOUNDATION");
        assertThat(capabilities.marketplaceEnabled()).isFalse();
        assertThat(capabilities.oidcIssuerConfigured()).isFalse();
        assertThat(capabilities.aiEnabled()).isFalse();
        assertThat(capabilities.autoEnabled()).isFalse();
        assertThat(capabilities.homeServicesEnabled()).isFalse();
        assertThat(capabilities.mapsEnabled()).isFalse();
    }

    @Test
    void reportsMapsOnlyWhenTheMapsProviderIsConfigured() {
        var toggles = TestToggles.of(new RidesFlags(false, false, false, false, false, false));
        assertThat(new PlatformController("", "", false, false, toggles, true).capabilities().mapsEnabled()).isTrue();
        assertThat(new PlatformController("", "", false, false, toggles, false).capabilities().mapsEnabled()).isFalse();
    }

    @Test
    void doesNotReportOidcConfiguredUntilIssuerAndAudienceArePresent() {
        var capabilities = new PlatformController("https://identity.example.test", "kunde-api", false, false,
                TestToggles.of(new RidesFlags(false, false, false, false, false, false))).capabilities();

        assertThat(capabilities.oidcIssuerConfigured()).isTrue();
        assertThat(capabilities.marketplaceEnabled()).isFalse();
        assertThat(capabilities.aiEnabled()).isFalse();
    }
}
