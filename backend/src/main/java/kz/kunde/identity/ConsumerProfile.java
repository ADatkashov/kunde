package kz.kunde.identity;

import java.time.Instant;
import java.util.UUID;

public record ConsumerProfile(UUID id, String displayName, String preferredLanguage, String status,
                              Instant createdAt, Instant updatedAt, long version) {}
