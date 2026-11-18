package kz.kunde.rides;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideRoutingController.Coordinates;
import kz.kunde.rides.RideRoutingController.RouteRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;

class RideRoutingControllerTest {
    private final RouteRequest request = new RouteRequest(
            new Coordinates(new BigDecimal("43.24"), new BigDecimal("76.92")),
            new Coordinates(new BigDecimal("43.25"), new BigDecimal("76.94")));

    @SuppressWarnings("unchecked")
    private final ObjectProvider<RideRouting> provider = mock(ObjectProvider.class);

    @Test
    void eitherFlagDisablesRouting() {
        for (var flags : List.of(flags(false, true), flags(true, false))) {
            var controller = new RideRoutingController(flags, provider);
            assertThatExceptionOfType(ApiException.class).isThrownBy(() -> controller.preview(request))
                    .satisfies(error -> assertThat(error.status()).isEqualTo(HttpStatus.NOT_FOUND));
        }
        verifyNoInteractions(provider);
    }

    @Test
    void missingProviderReturnsUnavailable() {
        var controller = new RideRoutingController(flags(true, true), provider);
        assertThatExceptionOfType(ApiException.class).isThrownBy(() -> controller.preview(request))
                .satisfies(error -> assertThat(error.code()).isEqualTo("RIDES_ROUTING_UNAVAILABLE"));
    }

    @Test
    void returnsTheProvidersRoadRouteWithNoStore() {
        var adapter = mock(RideRouting.class);
        when(provider.getIfAvailable()).thenReturn(adapter);
        var pickup = request.pickup().point();
        var destination = request.destination().point();
        var route = new RideRouting.Route(3000, 360, List.of(pickup, destination));
        when(adapter.route(pickup, destination)).thenReturn(Optional.of(route));

        var response = new RideRoutingController(flags(true, true), provider).preview(request);
        assertThat(response.getBody()).isEqualTo(route);
        assertThat(response.getHeaders().getCacheControl()).isEqualTo("no-store");
    }

    private static RidesFlags flags(boolean enabled, boolean consumer) {
        return new RidesFlags(enabled, consumer, false, false, false, false);
    }
}
