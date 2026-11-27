package kz.kunde.delivery;

import java.util.UUID;
import kz.kunde.platform.courier.CourierDirectory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** In-process {@link CourierDirectory} over the Delivery courier registry. */
@Component
public class JdbcCourierDirectory implements CourierDirectory {
    private final JdbcTemplate db;

    public JdbcCourierDirectory(JdbcTemplate db) {
        this.db = db;
    }

    @Override
    public boolean isApprovedCourier(UUID userId, boolean mustBeOnline) {
        Integer ok = db.queryForObject("select count(*) from transactions.delivery_couriers where user_id = ? and status = 'APPROVED' and (not ? or online)",
                Integer.class, userId, mustBeOnline);
        return ok != null && ok > 0;
    }
}
