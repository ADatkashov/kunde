package kz.kunde.leisure;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * KUNDE Leisure. {@code enabled} left empty follows the environment: on in local/dev/test, off everywhere else (owner decision, PROD stays off
 * until a separate approval). An explicit value always wins, but {@code true} is refused outside local/dev/test.
 */
@ConfigurationProperties("app.leisure")
public record LeisureProperties(Boolean enabled, boolean seedDemo) {}
