package kz.kunde.rides;

import java.util.UUID;
import kz.kunde.platform.support.CaseSubjectOwnership;
import kz.kunde.platform.support.SupportCaseDirectory.Subject;
import org.springframework.stereotype.Component;

/** Lets Support attach a case to a ride only for the rider who owns it (same lookup and 404 as the rider's own endpoint). */
@Component
class RideCaseSubject implements CaseSubjectOwnership {
    private final RideRequestService rides;

    RideCaseSubject(RideRequestService rides) {
        this.rides = rides;
    }

    @Override
    public Subject subject() {
        return Subject.RIDE;
    }

    @Override
    public void requireOwnedBy(UUID owner, UUID rideId) {
        rides.get(owner, rideId);
    }
}
