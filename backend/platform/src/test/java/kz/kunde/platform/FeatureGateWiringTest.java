package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import java.util.ArrayList;
import java.util.List;
import kz.kunde.platform.FeatureToggles.Feature;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

/** The kernel must not start with a product that has no gate (fail closed), and gates are the only source of the ceiling. */
class FeatureGateWiringTest {
    private static FeatureGate gate(Feature feature, boolean allowed) {
        return new FeatureGate() {
            public Feature feature() { return feature; }
            public boolean allowedByEnvironment() { return allowed; }
        };
    }

    private static List<FeatureGate> all(boolean allowed) {
        List<FeatureGate> gates = new ArrayList<>();
        for (Feature f : Feature.values()) {
            gates.add(gate(f, allowed));
        }
        return gates;
    }

    @Test
    void missingGateFailsStartup() {
        List<FeatureGate> gates = all(true);
        gates.removeIf(g -> g.feature() == Feature.BEAUTY);
        assertThatThrownBy(() -> new FeatureToggles(mock(JdbcTemplate.class), gates))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("BEAUTY");
    }

    @Test
    void duplicateGateFailsStartup() {
        List<FeatureGate> gates = all(true);
        gates.add(gate(Feature.AUTO, false));
        assertThatThrownBy(() -> new FeatureToggles(mock(JdbcTemplate.class), gates))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("AUTO");
    }

    @Test
    void environmentCeilingComesFromTheDomainGate() {
        List<FeatureGate> gates = all(true);
        gates.replaceAll(g -> g.feature() == Feature.EVENTS ? gate(Feature.EVENTS, false) : g);
        FeatureToggles toggles = new FeatureToggles(mock(JdbcTemplate.class), gates);
        assertThat(toggles.allowedByEnvironment(Feature.EVENTS)).isFalse();
        assertThat(toggles.allowedByEnvironment(Feature.AUTO)).isTrue();
    }

    @Test
    void liveViewAppliesTheMasterSwitchWithoutTheKernelKnowingTheDomain() {
        FeatureGate delegating = new FeatureGate() {
            public Feature feature() { return Feature.AUTO; }
            public boolean allowedByEnvironment() { return true; }
            public FeatureGate withEnabled(boolean master) { return this; }
            public java.util.Map<String, Boolean> capabilities() { return java.util.Map.of("x", true); }
        };
        List<FeatureGate> gates = all(true);
        gates.replaceAll(g -> g.feature() == Feature.AUTO ? delegating : g);
        FeatureToggles toggles = new FeatureToggles(mock(JdbcTemplate.class), gates);
        assertThat(toggles.capabilities(Feature.AUTO)).containsEntry("x", true);
        assertThat(toggles.capabilities(Feature.EVENTS)).isEmpty();
    }
}
