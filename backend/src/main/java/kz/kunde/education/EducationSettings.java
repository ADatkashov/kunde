package kz.kunde.education;

import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

@Component
public class EducationSettings {
    private final boolean allowed;

    public EducationSettings(Environment environment) {
        boolean internal = Set.of("local", "dev", "test").contains(environment.getProperty("app.environment", "production"))
                && !environment.acceptsProfiles(Profiles.of("prod", "production"));
        this.allowed = internal && environment.getProperty("app.education.enabled", Boolean.class, true);
    }

    public boolean allowedByEnvironment() {
        return allowed;
    }
}
