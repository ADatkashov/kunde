package kz.kunde.platform.placement;

import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Locator over a fixed SQL {@code select city_id from ... where <root>.id = ?}. The SQL is a compile-time constant of the
 * owning domain; the id is always a bind parameter.
 */
public class SqlPlacementLocator implements PlacementLocator {
    private final String aggregate;
    private final String domain;
    private final String sql;
    private final JdbcTemplate db;

    public SqlPlacementLocator(String aggregate, String domain, String sql, JdbcTemplate db) {
        this.aggregate = aggregate;
        this.domain = domain;
        this.sql = sql;
        this.db = db;
    }

    @Override
    public String aggregate() {
        return aggregate;
    }

    @Override
    public String domain() {
        return domain;
    }

    @Override
    public Optional<Placement> locate(UUID aggregateId) {
        return db.query(sql, (rs, row) -> new Placement(aggregateId, rs.getObject(1, UUID.class)), aggregateId)
                .stream().findFirst();
    }
}
