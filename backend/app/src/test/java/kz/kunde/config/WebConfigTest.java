package kz.kunde.config;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class WebConfigTest {
    @Test
    void acceptsOnlyExplicitOriginsWithoutCredentialsOrPaths() {
        assertThatCode(() -> new WebConfig("https://app.example.test,http://localhost:3000")).doesNotThrowAnyException();
        assertThatCode(() -> new WebConfig("   ")).doesNotThrowAnyException();
        assertThatThrownBy(() -> new WebConfig("https://app.example.test/path"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new WebConfig("https://user:pass@app.example.test"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
