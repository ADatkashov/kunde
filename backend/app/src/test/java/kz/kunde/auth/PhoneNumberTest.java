package kz.kunde.auth;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class PhoneNumberTest {
    @ParameterizedTest
    @ValueSource(strings = {"+77000000001", "+7 700 000 00 01", "8 (700) 000-00-01", "87000000001", "77000000001", "007 700 000 0001"})
    void normalizesKazakhstanForms(String input) {
        assertThat(PhoneNumber.normalize(input)).contains("+77000000001");
    }

    @ParameterizedTest
    @ValueSource(strings = {"", " ", "abc", "+0123456789", "+7700", "+7700000000000000000", "700000001", "+7 700 000 00 0a",
            "+77000000001; DROP TABLE users"})
    void rejectsInvalidInput(String input) {
        assertThat(PhoneNumber.normalize(input)).isEmpty();
    }

    @Test
    void rejectsNullAndOversizedInput() {
        assertThat(PhoneNumber.normalize(null)).isEmpty();
        assertThat(PhoneNumber.normalize("+" + "7".repeat(40))).isEmpty();
    }

    @Test
    void acceptsOtherCountriesInE164() {
        assertThat(PhoneNumber.normalize("+44 20 7946 0958")).contains("+442079460958");
    }
}
