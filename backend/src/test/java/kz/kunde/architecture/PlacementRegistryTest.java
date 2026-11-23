package kz.kunde.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * Fast (no Spring, no database) guard for the data-placement model that future sharding by city depends on
 * (docs/architecture/database-sharding-readiness.md). It reads the real Flyway files and Java sources:
 * every table must be classified, every aggregate root must really carry an immutable {@code city_id}, children
 * must not duplicate it, and nothing may take a city from a request header.
 */
class PlacementRegistryTest {
    private static final Path MIGRATIONS = Path.of("src/main/resources/db/migration");
    private static final Path SOURCES = Path.of("src/main/java/kz/kunde");
    private static final String REGISTRY = "/architecture/placement-registry.txt";

    private static final Pattern CREATE_TABLE =
            Pattern.compile("create\\s+table\\s+(?:if\\s+not\\s+exists\\s+)?(\\w+\\.\\w+)", Pattern.CASE_INSENSITIVE);
    private static final Pattern ADD_CITY = Pattern.compile(
            "alter\\s+table\\s+(\\w+\\.\\w+)\\s+add\\s+column\\s+city_id\\s+uuid", Pattern.CASE_INSENSITIVE);
    private static final Pattern CITY_TRIGGER = Pattern.compile(
            "create\\s+trigger\\s+\\w+\\s+before\\s+update\\s+of\\s+city_id\\s+on\\s+(\\w+\\.\\w+)", Pattern.CASE_INSENSITIVE);

    private record Entry(String prefix, String kind, String arg) {}

    @Test
    void everyTableIsClassifiedForPlacement() {
        List<String> missing = new ArrayList<>();
        for (String table : migratedTables()) {
            if (entryOf(table) == null) {
                missing.add(table);
            }
        }
        assertThat(missing)
                .as("Tables without a placement class in src/test/resources/architecture/placement-registry.txt. "
                        + "Decide GLOBAL / CITY_ROOT / CITY_CHILD / EXECUTOR, or UNDECIDED with a reason, when you add a table.")
                .isEmpty();
    }

    @Test
    void everyCityRootHasAnImmutableCityIdAndNothingElseDoes() {
        Map<String, String> sql = migrationSql();
        Set<String> withColumn = new TreeSet<>(matches(ADD_CITY, sql.values()));
        Set<String> withTrigger = new TreeSet<>(matches(CITY_TRIGGER, sql.values()));
        Set<String> roots = new TreeSet<>();
        for (String table : migratedTables()) {
            Entry e = entryOf(table);
            if (e != null && e.kind().equals("CITY_ROOT")) {
                roots.add(table);
            }
        }
        assertThat(roots).as("aggregate roots").isNotEmpty();
        assertThat(withColumn).as("tables that add city_id must be exactly the CITY_ROOT tables (children inherit)")
                .isEqualTo(roots);
        assertThat(withTrigger).as("every placement key is protected by the immutability trigger").isEqualTo(roots);
    }

    @Test
    void childrenPointAtARealPlacedParent() {
        Set<String> tables = migratedTables();
        List<String> broken = new ArrayList<>();
        for (String table : tables) {
            Entry e = entryOf(table);
            if (e == null || !e.kind().equals("CITY_CHILD")) {
                continue;
            }
            Entry parent = tables.contains(e.arg()) ? entryOf(e.arg()) : null;
            if (parent == null || !(parent.kind().equals("CITY_ROOT") || parent.kind().equals("CITY_CHILD"))) {
                broken.add(table + " -> " + e.arg());
            }
            if (e.arg().equals(table)) {
                broken.add(table + " is its own parent");
            }
        }
        assertThat(broken).as("CITY_CHILD tables whose parent is missing or not city-placed").isEmpty();
    }

    @Test
    void undecidedTablesAlwaysSayWhy() {
        List<String> blank = new ArrayList<>();
        for (String table : migratedTables()) {
            Entry e = entryOf(table);
            if (e != null && e.kind().equals("UNDECIDED") && (e.arg() == null || e.arg().strip().length() < 15)) {
                blank.add(table);
            }
        }
        assertThat(blank).as("UNDECIDED needs a concrete reason").isEmpty();
    }

    @Test
    void noEndpointTakesTheOwningCityFromARequestHeader() {
        Pattern header = Pattern.compile("@RequestHeader\\s*\\([^)]*city", Pattern.CASE_INSENSITIVE);
        Pattern raw = Pattern.compile("getHeader\\s*\\(\\s*\"[^\"]*city", Pattern.CASE_INSENSITIVE);
        List<String> offenders = new ArrayList<>();
        for (Path file : javaFiles()) {
            String text = read(file);
            if (header.matcher(text).find() || raw.matcher(text).find()) {
                offenders.add(file.getFileName().toString());
            }
        }
        assertThat(offenders)
                .as("City must come from stored data (PlacementService) or from an authorization-checked grant, never trusted from a header")
                .isEmpty();
    }

    // ---------------------------------------------------------------- helpers

    private static Set<String> matches(Pattern pattern, Iterable<String> texts) {
        Set<String> out = new TreeSet<>();
        for (String text : texts) {
            Matcher m = pattern.matcher(text);
            while (m.find()) {
                out.add(m.group(1).toLowerCase());
            }
        }
        return out;
    }

    private static Entry entryOf(String table) {
        for (String line : resource(REGISTRY)) {
            if (line.isBlank() || line.startsWith("#")) {
                continue;
            }
            String[] kv = line.split("=", 2);
            if (!table.startsWith(kv[0].trim())) {
                continue;
            }
            String value = kv[1].trim();
            int colon = value.indexOf(':');
            return colon < 0 ? new Entry(kv[0].trim(), value, null)
                    : new Entry(kv[0].trim(), value.substring(0, colon), value.substring(colon + 1).trim());
        }
        return null;
    }

    private static Set<String> migratedTables() {
        Set<String> tables = new TreeSet<>();
        for (String text : migrationSql().values()) {
            Matcher m = CREATE_TABLE.matcher(text);
            while (m.find()) {
                tables.add(m.group(1).toLowerCase());
            }
        }
        return tables;
    }

    private static Map<String, String> migrationSql() {
        Map<String, String> out = new TreeMap<>();
        try (Stream<Path> walk = Files.list(MIGRATIONS)) {
            for (Path sql : walk.filter(p -> p.toString().endsWith(".sql")).toList()) {
                out.put(sql.getFileName().toString(), read(sql));
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return out;
    }

    private static List<Path> javaFiles() {
        try (Stream<Path> walk = Files.walk(SOURCES)) {
            return walk.filter(p -> p.toString().endsWith(".java")).sorted().toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static String read(Path file) {
        try {
            return Files.readString(file);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static List<String> resource(String name) {
        try (var in = PlacementRegistryTest.class.getResourceAsStream(name)) {
            if (in == null) {
                throw new IllegalStateException("Missing test resource " + name);
            }
            return new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).lines().toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
