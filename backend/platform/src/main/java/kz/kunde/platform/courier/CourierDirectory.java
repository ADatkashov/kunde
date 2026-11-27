package kz.kunde.platform.courier;

import java.util.UUID;

/**
 * What other products may ask about couriers without reading Delivery's tables: the courier registry (approved profile,
 * online or not) is owned by Delivery and a person registers there once, then takes hand-off tasks of any product
 * (Food, Groceries, Flowers). Same idea as {@code PartnerDirectory}: a snapshot answer, role rules stay with the owner.
 */
public interface CourierDirectory {
    /** The user has an APPROVED courier profile; with {@code mustBeOnline} the courier must also be online. */
    boolean isApprovedCourier(UUID userId, boolean mustBeOnline);
}
