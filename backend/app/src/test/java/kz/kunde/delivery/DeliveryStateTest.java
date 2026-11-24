package kz.kunde.delivery;

import static org.assertj.core.api.Assertions.assertThat;

import kz.kunde.delivery.DeliveryState.Action;
import kz.kunde.delivery.DeliveryState.Actor;
import org.junit.jupiter.api.Test;

class DeliveryStateTest {
    @Test
    void onlyAConfirmedHandoffCanLeadToCompletion() {
        for (DeliveryState state : DeliveryState.values()) {
            if (state == DeliveryState.DELIVERED) {
                assertThat(state.transition(Actor.COURIER, Action.COMPLETE)).contains(DeliveryState.COMPLETED);
            } else {
                assertThat(state.transition(Actor.COURIER, Action.COMPLETE)).isEmpty();
            }
        }
        assertThat(DeliveryState.IN_TRANSIT.transition(Actor.COURIER, Action.VERIFY_HANDOFF)).isEmpty();
        assertThat(DeliveryState.IN_TRANSIT.transition(Actor.SYSTEM, Action.VERIFY_HANDOFF))
                .contains(DeliveryState.DELIVERED);
    }

    @Test
    void unsuccessfulHandoffRequiresAnOperatorAuthorizedReturn() {
        assertThat(DeliveryState.IN_TRANSIT.transition(Actor.COURIER, Action.FAIL_DELIVERY))
                .contains(DeliveryState.DELIVERY_FAILED);
        assertThat(DeliveryState.DELIVERY_FAILED.transition(Actor.CUSTOMER, Action.REQUEST_RETURN)).isEmpty();
        assertThat(DeliveryState.DELIVERY_FAILED.transition(Actor.COURIER, Action.START_RETURN)).isEmpty();
        assertThat(DeliveryState.DELIVERY_FAILED.transition(Actor.ADMIN, Action.REQUEST_RETURN))
                .contains(DeliveryState.RETURN_REQUESTED);
        assertThat(DeliveryState.RETURN_REQUESTED.transition(Actor.COURIER, Action.START_RETURN))
                .contains(DeliveryState.RETURNING);
        assertThat(DeliveryState.RETURNING.transition(Actor.COURIER, Action.CONFIRM_RETURN))
                .contains(DeliveryState.RETURNED_TO_SENDER);
        assertThat(DeliveryState.PICKED_UP.transition(Actor.CUSTOMER, Action.CANCEL)).isEmpty();
    }
}
