package kz.kunde.auth;

import java.util.Optional;
import java.util.regex.Pattern;

/** Normalizes user input to E.164 ({@code +<country><number>}, 8-15 digits). */
public final class PhoneNumber {
    private static final Pattern E164 = Pattern.compile("^\\+[1-9][0-9]{7,14}$");
    private static final Pattern SEPARATORS = Pattern.compile("[\\s().-]");

    private PhoneNumber() {}

    public static Optional<String> normalize(String raw) {
        if (raw == null || raw.length() > 32) return Optional.empty();
        String value = SEPARATORS.matcher(raw.strip()).replaceAll("");
        if (value.startsWith("00")) value = "+" + value.substring(2);
        if (!value.startsWith("+")) {
            if (!value.matches("[0-9]+")) return Optional.empty();
            // Kazakhstan/Russia national forms: 8 7XX XXX XX XX and 7 7XX XXX XX XX.
            if (value.length() == 11 && (value.startsWith("8") || value.startsWith("7"))) {
                value = "+7" + value.substring(1);
            } else {
                return Optional.empty();
            }
        }
        return E164.matcher(value).matches() ? Optional.of(value) : Optional.empty();
    }
}
