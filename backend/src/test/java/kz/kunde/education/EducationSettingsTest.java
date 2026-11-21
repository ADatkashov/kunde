package kz.kunde.education;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class EducationSettingsTest {
    @Test
    void enablesOnlyExplicitInternalEnvironments() {
        for (String name : new String[] {"local", "dev", "test"}) {
            var env = new MockEnvironment().withProperty("app.environment", name);
            assertThat(new EducationSettings(env).allowedByEnvironment()).isTrue();
            env.setProperty("app.education.enabled", "false");
            assertThat(new EducationSettings(env).allowedByEnvironment()).isFalse();
        }
        var env = new MockEnvironment().withProperty("app.education.enabled", "true");
        assertThat(new EducationSettings(env).allowedByEnvironment()).isFalse();
        env.setProperty("app.environment", "dev");
        env.setActiveProfiles("production");
        assertThat(new EducationSettings(env).allowedByEnvironment()).isFalse();
    }
}
