package kz.kunde.maps;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatIllegalStateException;

import com.fasterxml.jackson.databind.ObjectMapper;
import kz.kunde.rides.RideRouting;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.mock.env.MockEnvironment;

class MapsConfigurationTest {
    private static final String ROUTING = "https://routing.maps.example";
    private static final String SEARCH = "https://search.maps.example";

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(MapsConfiguration.class)
            .withBean(ObjectMapper.class, ObjectMapper::new);

    @Test
    void isOffByDefaultSoRidesKeepFailingClosed() {
        runner.run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).doesNotHaveBean(RideRouting.class);
        });
    }

    @Test
    void providesTheMapsBackedRoutingWhenEnabled() {
        runner.withPropertyValues("app.maps.enabled=true", "app.maps.routing-url=" + ROUTING, "app.maps.search-url=" + SEARCH)
                .run(context -> assertThat(context).hasSingleBean(RideRouting.class)
                        .getBean(RideRouting.class).isInstanceOf(KundeMapsRideRouting.class));
    }

    @Test
    void enabledWithoutSecureUrlsFailsStartup() {
        for (var values : new String[][] {
                {"app.maps.enabled=true"},
                {"app.maps.enabled=true", "app.maps.routing-url=" + ROUTING},
                {"app.maps.enabled=true", "app.maps.routing-url=http://insecure.example", "app.maps.search-url=" + SEARCH}}) {
            runner.withPropertyValues(values).run(context -> assertThat(context).hasFailed());
        }
    }

    @Test
    void cannotBeCombinedWithSyntheticRouting() {
        var maps = new MapsProperties(true, ROUTING, SEARCH, "", 0, 0);
        for (var flag : new String[] {"app.rides.synthetic-routing-enabled", "app.delivery.synthetic-routing-enabled"}) {
            var environment = new MockEnvironment().withProperty(flag, "true");
            assertThatIllegalStateException().isThrownBy(() -> new MapsConfiguration(maps, environment));
        }
        assertThatCode(() -> new MapsConfiguration(maps, new MockEnvironment())).doesNotThrowAnyException();
        assertThatCode(() -> new MapsConfiguration(new MapsProperties(false, "", "", "", 0, 0),
                new MockEnvironment().withProperty("app.rides.synthetic-routing-enabled", "true"))).doesNotThrowAnyException();
    }

    @Test
    void propertiesGetSafeDefaults() {
        var defaults = new MapsProperties(false, null, null, null, 0, 0);
        assertThat(defaults.timeoutSeconds()).isEqualTo(15);
        assertThat(defaults.maxResponseBytes()).isEqualTo(524_288);
        assertThat(defaults.apiKey()).isEmpty();
    }
}
