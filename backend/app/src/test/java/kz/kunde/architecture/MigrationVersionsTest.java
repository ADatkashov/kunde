package kz.kunde.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * Fast (no Spring, no database) guard for Flyway versions. Two branches may each add the next free version and both pass their
 * own CI; once both are merged the application refuses to start ("Found more than one migration with version N"). This test
 * fails on the merged tree before any deployment does.
 */
class MigrationVersionsTest {
    private static final Path MIGRATIONS = Path.of("src/main/resources/db/migration");
    private static final Pattern VERSIONED = Pattern.compile("V(\\d+)__.+\\.sql");

    @Test
    void everyMigrationVersionIsUnique() throws IOException {
        Map<Long, List<String>> byVersion = new TreeMap<>();
        try (Stream<Path> files = Files.list(MIGRATIONS)) {
            files.map(path -> path.getFileName().toString()).sorted().forEach(name -> {
                Matcher matcher = VERSIONED.matcher(name);
                if (matcher.matches()) {
                    byVersion.computeIfAbsent(Long.parseLong(matcher.group(1)), key -> new java.util.ArrayList<>()).add(name);
                }
            });
        }
        assertThat(byVersion).as("versioned migrations found").isNotEmpty();
        Map<Long, List<String>> duplicates = byVersion.entrySet().stream()
                .filter(entry -> entry.getValue().size() > 1)
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue, (a, b) -> a, TreeMap::new));
        assertThat(duplicates).as("Flyway versions used by more than one file").isEmpty();
    }

    @Test
    void versionsHaveNoGaps() throws IOException {
        List<Long> versions;
        try (Stream<Path> files = Files.list(MIGRATIONS)) {
            versions = files.map(path -> VERSIONED.matcher(path.getFileName().toString()))
                    .filter(Matcher::matches).map(matcher -> Long.parseLong(matcher.group(1))).sorted().distinct().toList();
        }
        for (int i = 1; i < versions.size(); i++) {
            assertThat(versions.get(i)).as("version after V" + versions.get(i - 1)).isEqualTo(versions.get(i - 1) + 1);
        }
    }
}
