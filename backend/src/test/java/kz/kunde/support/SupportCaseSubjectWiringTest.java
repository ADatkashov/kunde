package kz.kunde.support;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.support.CaseSubjectOwnership;
import kz.kunde.platform.support.SupportCaseDirectory.Subject;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

/** Support must not start without an ownership check for every subject kind: otherwise a case could link a foreign order. */
class SupportCaseSubjectWiringTest {
    private static CaseSubjectOwnership check(Subject subject) {
        return new CaseSubjectOwnership() {
            public Subject subject() { return subject; }
            public void requireOwnedBy(UUID owner, UUID subjectId) {}
        };
    }

    @Test
    void missingOwnershipCheckFailsStartup() {
        assertThatThrownBy(() -> new SupportCaseService(mock(JdbcTemplate.class), mock(ConsumerIdentityService.class),
                List.of(check(Subject.RIDE))))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("DELIVERY");
    }

    @Test
    void duplicateOwnershipCheckFailsStartup() {
        assertThatThrownBy(() -> new SupportCaseService(mock(JdbcTemplate.class), mock(ConsumerIdentityService.class),
                List.of(check(Subject.RIDE), check(Subject.RIDE), check(Subject.DELIVERY))))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("RIDE");
    }
}
