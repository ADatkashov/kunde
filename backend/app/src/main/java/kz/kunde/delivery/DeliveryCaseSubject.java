package kz.kunde.delivery;

import java.util.UUID;
import kz.kunde.platform.support.CaseSubjectOwnership;
import kz.kunde.platform.support.SupportCaseDirectory.Subject;
import org.springframework.stereotype.Component;

/** Lets Support attach a case to a delivery only for the sender who owns it (same lookup and 404 as the sender's own endpoint). */
@Component
class DeliveryCaseSubject implements CaseSubjectOwnership {
    private final DeliveryService deliveries;

    DeliveryCaseSubject(DeliveryService deliveries) {
        this.deliveries = deliveries;
    }

    @Override
    public Subject subject() {
        return Subject.DELIVERY;
    }

    @Override
    public void requireOwnedBy(UUID owner, UUID deliveryId) {
        deliveries.get(owner, null, deliveryId);
    }
}
