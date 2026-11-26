package kz.kunde.booking;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Component;

/** Registry of {@link BookingCategory} implementations; a category without a plug-in has no extra rules. */
@Component
public class BookingCategories {
    private final Map<String, BookingCategory> byCategory = new HashMap<>();

    public BookingCategories(List<BookingCategory> categories) {
        for (BookingCategory c : categories) {
            if (byCategory.put(c.category(), c) != null) {
                throw new IllegalStateException("More than one BookingCategory for " + c.category());
            }
        }
    }

    public void requireAvailable(String category) {
        BookingCategory c = byCategory.get(category);
        if (c != null) {
            c.requireAvailable();
        }
    }

    public Integer discountPercent(String category, UUID venueId) {
        BookingCategory c = byCategory.get(category);
        return c == null ? null : c.discountPercent(venueId);
    }

    public boolean confirmsInstantly(String category, UUID venueId) {
        BookingCategory c = byCategory.get(category);
        return c != null && c.confirmsInstantly(venueId);
    }

    public long surchargeMinor(String category, BookingCategory.PricingContext context) {
        BookingCategory c = byCategory.get(category);
        return c == null ? 0 : c.surchargeMinor(context);
    }
}
