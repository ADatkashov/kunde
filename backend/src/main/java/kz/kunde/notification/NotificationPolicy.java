package kz.kunde.notification;

import java.util.EnumSet;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * TASK-031 / PRD 1.1 §14: channel eligibility, deduplication and lock-screen text rules.
 * Contract only: no provider is selected (D-11), nothing is sent, queued or stored, and OTP,
 * marketing and payment notifications stay disabled until their gates are approved.
 */
public final class NotificationPolicy {
    public enum Channel { IN_APP, PUSH, SMS, EMAIL, MESSAGING }

    public enum Kind {
        SECURITY_MANDATORY(true), TRANSACTION_MANDATORY(true), FINANCIAL_MANDATORY(true),
        SERVICE_MANDATORY(true), USER_REQUESTED_OPERATIONAL(false), MARKETING_OPTIONAL(false);

        private final boolean mandatory;
        Kind(boolean mandatory) { this.mandatory = mandatory; }
        public boolean mandatory() { return mandatory; }
    }

    /** Recipient choices. Channels are the ones the user has enabled and that have a usable contact/token. */
    public record Preferences(Set<Channel> usableChannels, boolean marketingConsent, boolean operationalPush) {
        public Preferences {
            usableChannels = usableChannels.isEmpty() ? Set.of() : EnumSet.copyOf(usableChannels);
        }
    }

    private static final Pattern LONG_DIGITS = Pattern.compile("\\d{8,}");
    public static final int LOCK_SCREEN_MAX = 120;

    private NotificationPolicy() { }

    /**
     * IN_APP is the durable source of status and is always included. Mandatory kinds use every usable
     * channel; operational kinds only push when allowed; marketing needs consent and no quiet hours
     * and never uses IN_APP-only suppression of mandatory messages.
     */
    public static Set<Channel> eligibleChannels(Kind kind, Preferences prefs, boolean quietHours) {
        var result = EnumSet.of(Channel.IN_APP);
        if (kind.mandatory()) {
            result.addAll(prefs.usableChannels());
        } else if (kind == Kind.USER_REQUESTED_OPERATIONAL) {
            if (prefs.operationalPush() && prefs.usableChannels().contains(Channel.PUSH)) { result.add(Channel.PUSH); }
        } else if (prefs.marketingConsent() && !quietHours) {
            result.addAll(prefs.usableChannels());
        }
        return result;
    }

    /** Stable key: retries of one event to one recipient/channel never produce a second message. */
    public static String dedupKey(String eventId, String recipientId, Channel channel) {
        return require(eventId, "eventId") + "|" + require(recipientId, "recipientId") + "|" + channel.name();
    }

    /** Lock-screen text must be short and carry no long digit runs, e-mail addresses or links. */
    public static boolean safeForLockScreen(String text) {
        return text != null && !text.isBlank() && text.length() <= LOCK_SCREEN_MAX
                && !LONG_DIGITS.matcher(text).find() && text.indexOf('@') < 0 && !text.toLowerCase().contains("http");
    }

    private static String require(String v, String field) {
        if (v == null || v.isBlank() || v.indexOf('|') >= 0) { throw new IllegalArgumentException(field + " invalid"); }
        return v;
    }
}
