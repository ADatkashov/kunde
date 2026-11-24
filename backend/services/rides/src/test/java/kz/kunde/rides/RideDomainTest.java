package kz.kunde.rides;

import static kz.kunde.rides.RideState.*;
import static kz.kunde.rides.RideState.Action.*;
import static kz.kunde.rides.RideState.Actor.*;
import static org.assertj.core.api.Assertions.*;

import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class RideDomainTest {
    @Test
    void onlyAuthorizedActorsCanAdvanceInOrder() {
        var actions = List.of(SEARCH, ASSIGN, DEPART, ARRIVE, START, COMPLETE);
        var expected = List.of(SEARCHING_DRIVER, DRIVER_ASSIGNED, DRIVER_ARRIVING, DRIVER_ARRIVED, IN_PROGRESS, COMPLETED);
        RideState current = REQUESTED;

        for (int i = 0; i < actions.size(); i++) {
            var action = actions.get(i);
            var allowed = i < 2 ? SYSTEM : ASSIGNED_DRIVER;
            for (var actor : Actor.values()) {
                if (actor == allowed) {
                    assertThat(current.transition(actor, action)).contains(expected.get(i));
                } else {
                    assertThat(current.transition(actor, action)).isEmpty();
                }
            }
            current = expected.get(i);
        }
    }

    @Test
    void terminalStatesRejectEveryCommand() {
        for (var state : List.of(COMPLETED, CANCELLED_BY_CUSTOMER, CANCELLED_BY_DRIVER,
                CANCELLED_BY_SYSTEM, NO_DRIVER_AVAILABLE, FAILED)) {
            for (var actor : Actor.values()) {
                for (var action : Action.values()) {
                    assertThat(state.transition(actor, action)).isEmpty();
                }
            }
        }
    }

    @Test
    void cancellationAndTimeoutDependOnAssignmentAndPickup() {
        assertThat(SEARCHING_DRIVER.transition(SYSTEM, EXPIRE)).contains(NO_DRIVER_AVAILABLE);
        assertThat(SEARCHING_DRIVER.transition(ASSIGNED_DRIVER, CANCEL)).isEmpty();
        assertThat(DRIVER_ASSIGNED.transition(ASSIGNED_DRIVER, CANCEL)).contains(CANCELLED_BY_DRIVER);
        assertThat(DRIVER_ARRIVED.transition(CUSTOMER, CANCEL)).contains(CANCELLED_BY_CUSTOMER);
        assertThat(DRIVER_ARRIVED.transition(SYSTEM, CANCEL)).contains(CANCELLED_BY_SYSTEM);
        assertThat(IN_PROGRESS.transition(CUSTOMER, CANCEL)).isEmpty();
        assertThat(REQUESTED.transition(ASSIGNED_DRIVER, COMPLETE)).isEmpty();
    }

    @Test
    void pricesFractionalKilometersAndMinutesInKzt() {
        var tariff = new RideTariff("example", new BigDecimal("100"), new BigDecimal("50"),
                new BigDecimal("2"), new BigDecimal("120"), new BigDecimal("5"));
        assertThat(tariff.estimateKzt(1234, 70)).isEqualTo(new BigDecimal("169.03"));
        assertThat(tariff.estimateKzt(10, 10)).isEqualTo(new BigDecimal("120.00"));
        assertThatIllegalArgumentException().isThrownBy(() -> tariff.estimateKzt(0, 70));
    }
}
