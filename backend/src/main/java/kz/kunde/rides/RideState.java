package kz.kunde.rides;

import java.util.Optional;

public enum RideState {
    REQUESTED, SEARCHING_DRIVER, DRIVER_ASSIGNED, DRIVER_ARRIVING, DRIVER_ARRIVED,
    IN_PROGRESS, COMPLETED, CANCELLED_BY_CUSTOMER, CANCELLED_BY_DRIVER,
    CANCELLED_BY_SYSTEM, NO_DRIVER_AVAILABLE, FAILED;

    public enum Actor { CUSTOMER, ASSIGNED_DRIVER, SYSTEM }

    public enum Action { SEARCH, ASSIGN, DEPART, ARRIVE, START, COMPLETE, CANCEL, EXPIRE, FAIL }

    public Optional<RideState> transition(Actor actor, Action action) {
        RideState next = switch (this) {
            case REQUESTED -> switch (action) {
                case SEARCH -> actor == Actor.SYSTEM ? SEARCHING_DRIVER : null;
                case CANCEL -> cancellation(actor, false);
                case FAIL -> actor == Actor.SYSTEM ? FAILED : null;
                default -> null;
            };
            case SEARCHING_DRIVER -> switch (action) {
                case ASSIGN -> actor == Actor.SYSTEM ? DRIVER_ASSIGNED : null;
                case EXPIRE -> actor == Actor.SYSTEM ? NO_DRIVER_AVAILABLE : null;
                case CANCEL -> cancellation(actor, false);
                case FAIL -> actor == Actor.SYSTEM ? FAILED : null;
                default -> null;
            };
            case DRIVER_ASSIGNED -> beforePickup(actor, action, Action.DEPART, DRIVER_ARRIVING);
            case DRIVER_ARRIVING -> beforePickup(actor, action, Action.ARRIVE, DRIVER_ARRIVED);
            case DRIVER_ARRIVED -> beforePickup(actor, action, Action.START, IN_PROGRESS);
            case IN_PROGRESS -> action == Action.COMPLETE && actor == Actor.ASSIGNED_DRIVER ? COMPLETED : null;
            default -> null;
        };
        return Optional.ofNullable(next);
    }

    private static RideState beforePickup(Actor actor, Action action, Action advance, RideState next) {
        if (action == Action.CANCEL) {
            return cancellation(actor, true);
        }
        return action == advance && actor == Actor.ASSIGNED_DRIVER ? next : null;
    }

    private static RideState cancellation(Actor actor, boolean assigned) {
        return switch (actor) {
            case CUSTOMER -> CANCELLED_BY_CUSTOMER;
            case ASSIGNED_DRIVER -> assigned ? CANCELLED_BY_DRIVER : null;
            case SYSTEM -> CANCELLED_BY_SYSTEM;
        };
    }
}
