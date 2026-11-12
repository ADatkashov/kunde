package kz.kunde.platform;

import java.util.LinkedHashMap;
import java.util.concurrent.TimeUnit;
import java.util.function.LongSupplier;

/** Non-authoritative, bounded per-process budgets shared by API admission filters. */
final class FixedWindowQuota<K> {
    private final int requests;
    private final int capacity;
    private final long windowNanos;
    private final LongSupplier clock;
    // Insertion order is expiry order. Active entries are never evicted for new keys.
    private final LinkedHashMap<K, Window> entries = new LinkedHashMap<>();

    FixedWindowQuota(int requests, int windowSeconds, int capacity, LongSupplier clock) {
        if (requests < 1 || windowSeconds < 1 || windowSeconds > 3600 || capacity < 1) {
            throw new IllegalArgumentException("API rate limits must be positive; window must be at most 3600 seconds");
        }
        this.requests = requests;
        this.capacity = capacity;
        this.windowNanos = TimeUnit.SECONDS.toNanos(windowSeconds);
        this.clock = clock;
    }

    synchronized long acquire(K key) {
        long now = clock.getAsLong();
        var iterator = entries.entrySet().iterator();
        while (iterator.hasNext()) {
            if (now - iterator.next().getValue().start < windowNanos) break;
            iterator.remove();
        }
        Window window = entries.get(key);
        if (window == null) {
            if (entries.size() >= capacity) return retryAfter(now, entries.firstEntry().getValue().start);
            window = new Window(now);
            entries.put(key, window);
        }
        if (window.used >= requests) return retryAfter(now, window.start);
        window.used++;
        return 0;
    }

    private long retryAfter(long now, long start) {
        long remaining = windowNanos - (now - start);
        return Math.max(1, (remaining + TimeUnit.SECONDS.toNanos(1) - 1) / TimeUnit.SECONDS.toNanos(1));
    }

    private static final class Window {
        private final long start;
        private int used;

        private Window(long start) { this.start = start; }
    }
}
