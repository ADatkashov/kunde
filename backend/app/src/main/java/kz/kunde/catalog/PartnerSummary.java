package kz.kunde.catalog;

/** Public view of an APPROVED partner (TASK-016): identity only, no staff, status history or documents. */
public record PartnerSummary(String id, String displayName) {}
