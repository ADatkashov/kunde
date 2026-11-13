package kz.kunde.fulfillment;

/**
 * D-02 (approved 2026-11-13): phased hybrid fulfillment for Food Ordering. Only {@link #PICKUP} (phase A) is
 * supported; the other methods exist so contracts can be versioned and configured independently, and stay
 * disabled until their own acceptance gates are met. KUNDE operates no courier fleet.
 */
public enum FulfillmentMethod {
    PICKUP(true),
    MERCHANT_DELIVERY(false),
    THIRD_PARTY_DELIVERY(false);

    private final boolean supported;

    FulfillmentMethod(boolean supported) { this.supported = supported; }

    /** Whether this build implements the method. Enabling an unsupported method is rejected (fail closed). */
    public boolean supported() { return supported; }
}
