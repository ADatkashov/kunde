package kz.kunde.rides;

import kz.kunde.platform.geo.RoutingProvider;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.geo.Coordinates;
import kz.kunde.rides.RideRoutingController.RouteRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;

class RideRoutingControllerTest {
    private final RouteRequest request = new RouteRequest(
            new Coordinates(new BigDecimal("43.24"), new BigDecimal("76.92")),
            new Coordinates(new BigDecimal("43.25"), new BigDecimal("76.94")));

    @SuppressWarnings("unchecked")
    private final ObjectProvider<RoutingProvider> provider = mock(ObjectProvider.class);

    @Test
    void eitherFlagDisablesRouting() {
        for (var flags : List.of(flags(false, true), flags(true, false))) {
            var controller = new RideRoutingController(kz.kunde.platform.TestToggles.of(flags), provider);
            assertThatExceptionOfType(ApiException.class).isThrownBy(() -> controller.preview(request))
                    .satisfies(error -> assertThat(error.status()).isEqualTo(HttpStatus.NOT_FOUND));
        }
        verifyNoInteractions(provider);
    }

    @Test
    void missingProviderReturnsUnavailable() {
        var controller = new RideRoutingController(kz.kunde.platform.TestToggles.of(flags(true, true)), provider);
        assertThatExceptionOfType(ApiException.class).isThrownBy(() -> controller.preview(request))
                .satisfies(error -> assertThat(error.code()).isEqualTo("RIDES_ROUTING_UNAVAILABLE"));
    }

    @Test
    void returnsTheProvidersRoadRouteWithNoStore() {
        var adapter = mock(RoutingProvider.class);
        when(provider.getIfAvailable()).thenReturn(adapter);
        var pickup = request.pickup().point();
        var destination = request.destination().point();
        var route = new RoutingProvider.Route(3000, 360, List.of(pickup, destination));
        when(adapter.route(pickup, destination)).thenReturn(Optional.of(route));

        var response = new RideRoutingController(kz.kunde.platform.TestToggles.of(flags(true, true)), provider).preview(request);
        assertThat(response.getBody()).isEqualTo(route);
        assertThat(response.getHeaders().getCacheControl()).isEqualTo("no-store");
    }

    @Test
    void mapsProviderTimeoutToServiceUnavailable() {
        var adapter = mock(RoutingProvider.class);
        when(provider.getIfAvailable()).thenReturn(adapter);
        when(adapter.route(request.pickup().point(), request.destination().point()))
                .thenThrow(new RoutingProvider.Unavailable(new java.util.concurrent.TimeoutException()));
        var controller = new RideRoutingController(kz.kunde.platform.TestToggles.of(flags(true, true)), provider);
        assertThatExceptionOfType(ApiException.class).isThrownBy(() -> controller.preview(request))
                .satisfies(error -> {
                    assertThat(error.status()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
                    assertThat(error.code()).isEqualTo("RIDES_ROUTING_UNAVAILABLE");
                });
    }

    @Test
    void rejectsSingleCharacterAfterTrimming() {
        var controller = new RideRoutingController(kz.kunde.platform.TestToggles.of(flags(true, true)), provider);
        var search = new RideRoutingController.SearchRequest(" a ", RideRoutingController.Language.en);
        assertThatExceptionOfType(ApiException.class).isThrownBy(() -> controller.search(search))
                .satisfies(error -> assertThat(error.status()).isEqualTo(HttpStatus.BAD_REQUEST));
        verifyNoInteractions(provider);
    }

    private static RidesFlags flags(boolean enabled, boolean consumer) {
        return new RidesFlags(enabled, consumer, false, false, false, false);
    }
}
