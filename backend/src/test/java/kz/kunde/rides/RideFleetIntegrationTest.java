package kz.kunde.rides;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideDriverService.Decision;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = {
        "app.environment=test", "app.identity.consumer-enabled=true", "app.rides.enabled=true",
        "app.rides.partner-enabled=true"
})
@Transactional
class RideFleetIntegrationTest {
    @Autowired JdbcTemplate db;
    @Autowired RideFleetService fleets;

    @Test
    void enforcesTenantScopeAndRecordsAnImmutableDecisionHistory() {
        UUID owner = user();
        UUID otherOwner = user();
        UUID reviewer = user();
        UUID driver = user();
        UUID fleet = partner(owner);
        UUID otherFleet = partner(otherOwner);
        staff(fleet, driver, "OPERATOR", owner);
        db.update("insert into transactions.ride_drivers (user_id, display_name) values (?, 'Candidate')", driver);

        assertThat(fleets.apply(owner, fleet).status()).isEqualTo("PENDING");
        assertThatThrownBy(() -> fleets.review(owner, fleet, Decision.APPROVED)).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> fleets.assignment(owner, fleet, driver, true)).isInstanceOf(ApiException.class);
        fleets.review(reviewer, fleet, Decision.APPROVED);
        assertThat(fleets.assignment(owner, fleet, driver, true).drivers())
                .extracting(RideFleetService.Driver::id).containsExactly(driver);

        fleets.apply(otherOwner, otherFleet);
        fleets.review(reviewer, otherFleet, Decision.APPROVED);
        assertThat(fleets.view(otherOwner, otherFleet).drivers()).isEmpty();
        assertThatThrownBy(() -> fleets.view(otherOwner, fleet)).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> fleets.assignment(otherOwner, otherFleet, driver, false)).isInstanceOf(ApiException.class);
        assertThat(fleets.assignment(owner, fleet, driver, false).drivers()).isEmpty();
        assertThat(fleets.audit(fleet)).extracting(RideFleetService.FleetEvent::action)
                .containsExactly("DETACHED", "ATTACHED", "APPROVED", "APPLIED");
    }

    private UUID user() {
        return db.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    private UUID partner(UUID owner) {
        UUID partner = db.queryForObject("""
                insert into marketplace.partners (display_name, verification_status, created_by_user_id)
                values ('Synthetic fleet', 'APPROVED', ?) returning id
                """, UUID.class, owner);
        staff(partner, owner, "OWNER", owner);
        return partner;
    }

    private void staff(UUID partner, UUID user, String role, UUID actor) {
        db.update("""
                insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id)
                values (?, ?, ?, ?)
                """, partner, user, role, actor);
    }
}
