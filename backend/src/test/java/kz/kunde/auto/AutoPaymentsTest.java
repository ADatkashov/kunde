package kz.kunde.auto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class AutoPaymentsTest {
    @Test
    void testCardExistsOnlyInNonProductionEnvironments() {
        assertThat(new AutoPayments(null, new MockEnvironment().withProperty("app.environment", "dev")).method("TEST_CARD")).isEqualTo("TEST_CARD");
        assertThat(new AutoPayments(null, new MockEnvironment().withProperty("app.environment", "test")).method(null)).isEqualTo("PAY_ON_SITE");
        var production = new AutoPayments(null, new MockEnvironment().withProperty("app.environment", "production"));
        assertThat(production.method("PAY_ON_SITE")).isEqualTo("PAY_ON_SITE");
        assertThatThrownBy(() -> production.method("TEST_CARD")).isInstanceOf(ApiException.class).hasMessageContaining("DEV/TEST");
        assertThatThrownBy(() -> production.method("CARD")).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> new AutoPayments(null, new MockEnvironment()).method("TEST_CARD")).isInstanceOf(ApiException.class);
    }
}
