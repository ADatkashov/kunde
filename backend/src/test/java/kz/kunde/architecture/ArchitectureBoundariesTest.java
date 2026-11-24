package kz.kunde.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * Fast (no Spring, no database) guard for the modular-monolith boundaries, so that a domain stays extractable
 * into its own service later (docs/architecture/microservice-readiness.md).
 *
 * <p>Two kinds of coupling are tracked, both derived from the real sources, not from documentation:
 * <ul>
 *   <li><b>IMPORT</b> - a class of module A imports a class of module B (a compile-time dependency);</li>
 *   <li><b>SQL</b> - code of module A names a table owned by module B (a shared-database dependency).</li>
 * </ul>
 * Existing coupling is frozen in {@code architecture/cross-module-baseline.txt}. The test is a ratchet: a <em>new</em>
 * cross-module dependency fails the build, and a <em>removed</em> one must be deleted from the baseline, so the debt
 * can only shrink. To add a dependency on purpose, put it in the baseline in the same PR and explain it there.
 */
class ArchitectureBoundariesTest {
    private static final Path SOURCES = Path.of("src/main/java/kz/kunde");
    private static final Path MIGRATIONS = Path.of("src/main/resources/db/migration");
    private static final String BASELINE = "/architecture/cross-module-baseline.txt";
    private static final String OWNERS = "/architecture/table-owners.txt";
    /** Module edges the target architecture records on purpose (ADR-023): a vertical product on its engine's public API and tables. */
    private static final String ALLOWED_EDGES = "/architecture/allowed-module-edges.txt";

    /** Shared kernel: infrastructure and consumer identity that every domain may import freely. */
    private static final Set<String> IMPORT_KERNEL = Set.of("platform", "identity");
    /** The composition root only wires modules together. */
    private static final Set<String> IMPORT_EXEMPT_SOURCES = Set.of("config");
    /** SQL by the composition root is not expected; auth/identity user tables are tracked like any other. */
    private static final Set<String> SQL_EXEMPT_SOURCES = Set.of("config");

    private static final Pattern IMPORT = Pattern.compile("^import\\s+(?:static\\s+)?kz\\.kunde\\.(\\w+)\\.([\\w.]+);");
    private static final Pattern CREATE_TABLE =
            Pattern.compile("create\\s+table\\s+(?:if\\s+not\\s+exists\\s+)?(\\w+\\.\\w+)", Pattern.CASE_INSENSITIVE);

    @Test
    void newCrossModuleCouplingIsRejectedAndFixedCouplingIsRemovedFromBaseline() {
        Set<String> actual = new TreeSet<>();
        actual.addAll(importCoupling());
        actual.addAll(sqlCoupling());
        actual.removeIf(ArchitectureBoundariesTest::isRecordedEdge);
        if (Boolean.getBoolean("kunde.architecture.updateBaseline")) {
            writeBaseline(actual);
        }
        Set<String> baseline = baseline();

        Set<String> added = new TreeSet<>(actual);
        added.removeAll(baseline);
        Set<String> removed = new TreeSet<>(baseline);
        removed.removeAll(actual);

        assertThat(added)
                .as("New cross-module dependency. Prefer a narrow interface in the owner module (or the shared kernel) "
                        + "over importing its classes or reading its tables. If it is deliberate, add the line to "
                        + "src/test/resources/architecture/cross-module-baseline.txt in the same PR and justify it in the PR.")
                .isEmpty();
        assertThat(removed)
                .as("Dependency no longer exists - delete these lines from src/test/resources/architecture/"
                        + "cross-module-baseline.txt so the debt cannot grow back unnoticed")
                .isEmpty();
    }

    @Test
    void everyTableHasADeclaredOwner() {
        List<String> orphans = new ArrayList<>();
        for (String table : migratedTables()) {
            if (ownerOf(table) == null) {
                orphans.add(table);
            }
        }
        assertThat(orphans)
                .as("Tables without an owner in src/test/resources/architecture/table-owners.txt")
                .isEmpty();
    }

    @Test
    void platformKernelDoesNotDependOnBusinessDomains() {
        // platform is the technical kernel: no import of a business domain is allowed (microservice-readiness V1).
        Set<String> offenders = new TreeSet<>();
        for (String edge : importCoupling()) {
            if (edge.startsWith("IMPORT platform/")) {
                offenders.add(edge);
            }
        }
        assertThat(offenders).as("platform must stay free of business domains").isEmpty();
    }

    // ---------------------------------------------------------------- coupling extraction

    private static Set<String> importCoupling() {
        Set<String> edges = new TreeSet<>();
        for (Path file : javaFiles()) {
            String module = moduleOf(file);
            if (IMPORT_EXEMPT_SOURCES.contains(module)) {
                continue;
            }
            for (String line : lines(file)) {
                Matcher m = IMPORT.matcher(line);
                if (!m.find()) {
                    continue;
                }
                String target = m.group(1);
                if (target.equals(module) || (IMPORT_KERNEL.contains(target) && !module.equals("platform"))) {
                    continue;
                }
                edges.add("IMPORT " + module + "/" + file.getFileName() + " -> " + target + "." + topLevelType(m.group(2)));
            }
        }
        return edges;
    }

    private static Set<String> sqlCoupling() {
        Set<String> tables = migratedTables();
        Pattern ref = Pattern.compile("\\b((?:identity|profile|marketplace|transactions|payments|support|serviceability|platform)\\.\\w+)\\b");
        Set<String> edges = new TreeSet<>();
        for (Path file : javaFiles()) {
            String module = moduleOf(file);
            if (SQL_EXEMPT_SOURCES.contains(module)) {
                continue;
            }
            for (String line : lines(file)) {
                Matcher m = ref.matcher(line);
                while (m.find()) {
                    String table = m.group(1);
                    String owner = tables.contains(table) ? ownerOf(table) : null;
                    if (owner != null && !owner.equals(module)) {
                        edges.add("SQL " + module + "/" + file.getFileName() + " -> " + table + " (owner " + owner + ")");
                    }
                }
            }
        }
        return edges;
    }

    // ---------------------------------------------------------------- helpers

    private static boolean isRecordedEdge(String coupling) {
        Matcher m = Pattern.compile("^(?:IMPORT|SQL) (\\w+)/\\S+ -> (?:(\\w+)\\.\\w+$|.* \\(owner (\\w+)\\)$)").matcher(coupling);
        if (!m.find()) {
            return false;
        }
        String target = m.group(2) != null ? m.group(2) : m.group(3);
        return resource(ALLOWED_EDGES).stream().map(String::trim).anyMatch(l -> l.equals(m.group(1) + " -> " + target));
    }

    private static String topLevelType(String name) {
        // kz.kunde.<module>.<Type>[.Nested] -> <Type>
        int dot = name.indexOf('.');
        return dot < 0 ? name : name.substring(0, dot);
    }

    private static String moduleOf(Path file) {
        return SOURCES.relativize(file).getName(0).toString();
    }

    private static List<Path> javaFiles() {
        try (Stream<Path> walk = Files.walk(SOURCES)) {
            return walk.filter(p -> p.toString().endsWith(".java")).sorted().toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static List<String> lines(Path file) {
        try {
            return Files.readAllLines(file);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static Set<String> migratedTables() {
        Set<String> tables = new TreeSet<>();
        try (Stream<Path> walk = Files.list(MIGRATIONS)) {
            for (Path sql : walk.filter(p -> p.toString().endsWith(".sql")).toList()) {
                Matcher m = CREATE_TABLE.matcher(String.join("\n", lines(sql)));
                while (m.find()) {
                    tables.add(m.group(1).toLowerCase());
                }
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return tables;
    }

    private static String ownerOf(String table) {
        TreeMap<Integer, String> ordered = new TreeMap<>();
        int order = 0;
        for (String line : resource(OWNERS)) {
            if (line.isBlank() || line.startsWith("#")) {
                continue;
            }
            String[] kv = line.split("=", 2);
            if (table.startsWith(kv[0].trim())) {
                ordered.put(order, kv[1].trim());
            }
            order++;
        }
        return ordered.isEmpty() ? null : ordered.firstEntry().getValue();
    }

    private static Set<String> baseline() {
        Set<String> set = new TreeSet<>();
        for (String line : resource(BASELINE)) {
            if (!line.isBlank() && !line.startsWith("#")) {
                set.add(line.trim());
            }
        }
        return set;
    }

    /** {@code mvn test -Dtest=ArchitectureBoundariesTest -Dkunde.architecture.updateBaseline=true} regenerates the file. */
    private static void writeBaseline(Set<String> actual) {
        List<String> out = new ArrayList<>(List.of(
                "# Frozen cross-module coupling (ratchet). Generated by ArchitectureBoundariesTest; see that class and",
                "# docs/architecture/microservice-readiness.md. Remove lines as the debt is paid; add lines only on purpose.",
                "# IMPORT <module>/<File> -> <targetModule>.<Type>   compile-time dependency on another business module",
                "# SQL <module>/<File> -> <schema.table> (owner <m>)  query against a table owned by another module"));
        out.addAll(actual);
        try {
            Files.write(Path.of("src/test/resources" + BASELINE), out);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static List<String> resource(String name) {
        try (var in = ArchitectureBoundariesTest.class.getResourceAsStream(name)) {
            if (in == null) {
                throw new IllegalStateException("Missing test resource " + name);
            }
            return new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).lines().toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
