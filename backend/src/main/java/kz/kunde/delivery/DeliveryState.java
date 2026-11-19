package kz.kunde.delivery;

import java.util.Optional;

public enum DeliveryState {
    CREATED, SEARCHING_COURIER, COURIER_ASSIGNED, COURIER_ARRIVING, COURIER_ARRIVED,
    PICKED_UP, IN_TRANSIT, DELIVERED, COMPLETED, CANCELLED_BY_CUSTOMER,
    CANCELLED_BY_COURIER, CANCELLED_BY_SYSTEM, NO_COURIER_AVAILABLE, PICKUP_FAILED,
    DELIVERY_FAILED, RETURN_REQUESTED, RETURNING, RETURNED_TO_SENDER, DISPUTED;

    public enum Actor { CUSTOMER, COURIER, SYSTEM, ADMIN }

    public enum Action {
        SEARCH, ASSIGN, DEPART, ARRIVE, PICK_UP, TRANSIT, VERIFY_HANDOFF, COMPLETE,
        CANCEL, EXPIRE, FAIL_PICKUP, FAIL_DELIVERY, REQUEST_RETURN, START_RETURN, CONFIRM_RETURN, DISPUTE
    }

    public Optional<DeliveryState> transition(Actor actor, Action action) {
        if (action == Action.CANCEL && beforePickup()) {
            return Optional.ofNullable(switch (actor) {
                case CUSTOMER -> CANCELLED_BY_CUSTOMER;
                case SYSTEM -> CANCELLED_BY_SYSTEM;
                case COURIER -> switch (this) {
                    case COURIER_ASSIGNED, COURIER_ARRIVING, COURIER_ARRIVED -> CANCELLED_BY_COURIER;
                    default -> null;
                };
                default -> null;
            });
        }
        return Optional.ofNullable(switch (this) {
            case CREATED -> actor == Actor.SYSTEM && action == Action.SEARCH ? SEARCHING_COURIER : null;
            case SEARCHING_COURIER -> actor == Actor.SYSTEM ? switch (action) {
                case ASSIGN -> COURIER_ASSIGNED;
                case EXPIRE -> NO_COURIER_AVAILABLE;
                default -> null;
            } : null;
            case COURIER_ASSIGNED -> actor == Actor.COURIER && action == Action.DEPART ? COURIER_ARRIVING : null;
            case COURIER_ARRIVING -> actor == Actor.COURIER && action == Action.ARRIVE ? COURIER_ARRIVED : null;
            case COURIER_ARRIVED -> actor == Actor.COURIER ? switch (action) {
                case PICK_UP -> PICKED_UP;
                case FAIL_PICKUP -> PICKUP_FAILED;
                default -> null;
            } : null;
            case PICKED_UP -> actor == Actor.COURIER && action == Action.TRANSIT ? IN_TRANSIT : null;
            case IN_TRANSIT -> switch (action) {
                case VERIFY_HANDOFF -> actor == Actor.SYSTEM ? DELIVERED : null;
                case FAIL_DELIVERY -> actor == Actor.COURIER ? DELIVERY_FAILED : null;
                default -> null;
            };
            case DELIVERED -> actor == Actor.COURIER && action == Action.COMPLETE ? COMPLETED : null;
            case DELIVERY_FAILED -> actor == Actor.ADMIN && action == Action.REQUEST_RETURN ? RETURN_REQUESTED : null;
            case RETURN_REQUESTED -> actor == Actor.COURIER && action == Action.START_RETURN ? RETURNING : null;
            case RETURNING -> actor == Actor.COURIER && action == Action.CONFIRM_RETURN ? RETURNED_TO_SENDER : null;
            case COMPLETED, RETURNED_TO_SENDER -> actor == Actor.ADMIN && action == Action.DISPUTE ? DISPUTED : null;
            default -> null;
        });
    }

    private boolean beforePickup() {
        return switch (this) {
            case CREATED, SEARCHING_COURIER, COURIER_ASSIGNED, COURIER_ARRIVING, COURIER_ARRIVED -> true;
            default -> false;
        };
    }
}
