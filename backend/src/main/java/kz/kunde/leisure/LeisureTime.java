package kz.kunde.leisure;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;

/** Instants leave the API with the venue offset (Asia/Almaty, +05:00) so the apps show the wall clock of the venue, never the server's UTC. */
public final class LeisureTime {
    private LeisureTime() {}

    public static OffsetDateTime local(ResultSet rs, int column) throws SQLException {
        OffsetDateTime value = rs.getObject(column, OffsetDateTime.class);
        return value == null ? null : value.atZoneSameInstant(LeisureCatalogService.ALMATY).toOffsetDateTime();
    }
}
