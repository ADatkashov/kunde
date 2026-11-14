package kz.kunde.catalog;

/** Consumer view of a published offering; partner is always an APPROVED partner (TASK-016). */
public record Offering(String id, String categoryId, String kind, String nameRu, String nameKk, String nameEn,
        String partnerId, String partnerName) {}
