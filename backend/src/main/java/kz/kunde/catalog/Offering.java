package kz.kunde.catalog;

/**
 * Consumer view of a published offering; partner is always an APPROVED partner (TASK-016). {@code priceMinor} is the one
 * final price in KZT tiyn (D-04 DEV pilot: no KUNDE fee, service fee, promo or tax line); {@code available} is the partner's flag.
 */
public record Offering(String id, String categoryId, String kind, String nameRu, String nameKk, String nameEn,
        String partnerId, String partnerName, long priceMinor, String currency, boolean available) {}
