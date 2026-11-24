package kz.kunde.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Deque;
import java.util.HashMap;
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
 * Architecture fitness functions for microservice readiness (ADR-025, docs/architecture/fitness-functions.md).
 * Fast, no Spring and no database. Complements {@link ArchitectureBoundariesTest}, which freezes individual
 * cross-module edges: these tests guard the <em>shape</em> of the dependency graph.
 *
 * <p>Every "known" file is a ratchet: an entry can be deleted when the debt is paid, and a new entry is a
 * deliberate, reviewed decision - never a way to make a failing build green.
 */
class ArchitectureFitnessTest {
    private static final Path BACKEND = Path.of("..").normalize();
    private static final String KNOWN_CYCLES = "/architecture/known-coupling-cycles.txt";
    private static final String KNOWN_FKS = "/architecture/cross-owner-foreign-keys.txt";
    private static final Pattern GRADLE_PROJECT = Pattern.compile("project\\(\":([\\w:]+)\"\\)");
    private static final Pattern IMPORT_EDGE = Pattern.compile("^IMPORT (\\w+)/\\S+ -> (\\w+)\\.");
    private static final Pattern SQL_EDGE = Pattern.compile("^SQL (\\w+)/\\S+ -> \\S+ \\(owner (\\w+)\\)$");
    private static final Pattern FK = Pattern.compile("references\\s+(\\w+\\.\\w+)", Pattern.CASE_INSENSITIVE);
    private static final Pattern CREATE_TABLE =
            Pattern.compile("create\\s+table\\s+(?:if\\s+not\\s+exists\\s+)?(\\w+\\.\\w+)\\s*\\(", Pattern.CASE_INSENSITIVE);
    private static final Pattern ALTER_TABLE =
            Pattern.compile("alter\\s+table\\s+(?:if\\s+exists\\s+)?(?:only\\s+)?(\\w+\\.\\w+)", Pattern.CASE_INSENSITIVE);

    // ------------------------------------------------------------------ Gradle layering

    @Test
    void gradleModuleGraphIsLayeredAndAcyclic() {
        Map<String, Set<String>> graph = gradleGraph();
        assertThat(graph).as("backend/platform and backend/services/* must be discovered").containsKey(":platform");

        assertThat(graph.get(":platform"))
                .as("platform is the technical kernel and must not depend on any business module")
                .isEmpty();
        List<String> dependOnApp = new ArrayList<>();
        graph.forEach((module, deps) -> {
            if (deps.contains(":app")) {
                dependOnApp.add(module);
            }
        });
        assertThat(dependOnApp).as("the composition root :app must not be a dependency of a library module").isEmpty();
        graph.forEach((module, deps) -> {
            if (!module.equals(":platform")) {
                assertThat(deps).as(module + " must depend on :platform, not the other way round").doesNotContain(module);
            }
        });
        assertThat(stronglyConnected(graph)).as("Gradle module cycle").isEmpty();
    }

    // ------------------------------------------------------------------ coupling cycles

    /**
     * Compile-time and data coupling (imports and SQL against foreign tables, allowed vertical edges included) between
     * business modules must not form new cycles: a cycle is a set of domains that can only be extracted together.
     * The edges that lie on a cycle today are listed in {@code known-coupling-cycles.txt} and can only be removed.
     */
    @Test
    void domainCouplingHasNoNewCycles() {
        Set<String> actual = edgesInsideCycles(couplingGraph());
        if (Boolean.getBoolean("kunde.architecture.updateKnown")) {
            write(KNOWN_CYCLES, "Module-level coupling edges that lie on a dependency cycle (ratchet, ArchitectureFitnessTest)."
                    + " Format: <module> -> <module>. Delete a line when the edge stops being part of a cycle.", actual);
        }
        Set<String> known = lines(KNOWN_CYCLES);

        Set<String> added = new TreeSet<>(actual);
        added.removeAll(known);
        Set<String> gone = new TreeSet<>(known);
        gone.removeAll(actual);
        assertThat(added)
                .as("New coupling edge inside (or creating) a dependency cycle between domains: they could no longer be extracted "
                        + "independently. Break it with a contract owned by one side, or an event; do not add it to " + KNOWN_CYCLES)
                .isEmpty();
        assertThat(gone)
                .as("Edge is no longer on a cycle - delete it from src/test/resources" + KNOWN_CYCLES)
                .isEmpty();
    }

    /**
     * Writes the real coupling (count of imports/SQL references per module pair, allowed vertical edges included) to
     * {@code build/architecture/coupling.tsv}; {@code scripts/dev/architecture_matrix.py} turns it into the matrices in
     * docs/architecture. Always passes: it documents, the other tests enforce.
     */
    @Test
    void writesCouplingReportForDocs() throws IOException {
        Map<String, int[]> counts = new TreeMap<>();
        for (String edge : ArchitectureBoundariesTest.importCoupling()) {
            Matcher m = IMPORT_EDGE.matcher(edge);
            if (m.find()) {
                counts.computeIfAbsent(m.group(1) + "\t" + m.group(2), k -> new int[2])[0]++;
            }
        }
        for (String edge : ArchitectureBoundariesTest.sqlCoupling()) {
            Matcher m = SQL_EDGE.matcher(edge);
            if (m.find()) {
                counts.computeIfAbsent(m.group(1) + "\t" + m.group(2), k -> new int[2])[1]++;
            }
        }
        List<String> out = new ArrayList<>();
        out.add("from\tto\timports\tsql");
        counts.forEach((k, v) -> out.add(k + "\t" + v[0] + "\t" + v[1]));
        Path target = Path.of("build/architecture/coupling.tsv");
        Files.createDirectories(target.getParent());
        Files.write(target, out);
    }

    // ------------------------------------------------------------------ public-contract hygiene

    @Test
    void foreignModulesDoNotImportControllersOrBootstrapClasses() {
        List<String> offenders = new ArrayList<>();
        for (String edge : ArchitectureBoundariesTest.importCoupling()) {
            Matcher m = Pattern.compile("^IMPORT \\w+/\\S+ -> (\\w+)\\.(\\w+)$").matcher(edge);
            if (m.find() && m.group(2).matches(".*(Controller|Filter|Config|Configuration)$")) {
                offenders.add(edge);
            }
        }
        assertThat(offenders)
                .as("A module may depend on another module's service/contract types, never on its web layer or wiring")
                .isEmpty();
    }

    @Test
    void servletTypesStayInTheWebLayer() {
        List<String> offenders = new ArrayList<>();
        for (Path file : ModuleSources.javaFiles()) {
            String name = file.getFileName().toString();
            if (name.matches(".*(Controller|Filter|ExceptionHandler|Advice)\\w*\\.java")) {
                continue;
            }
            String module = ModuleSources.moduleOf(file);
            if (module.equals("config") || module.equals("platform")) {
                continue; // the technical kernel owns the web plumbing (security filters, error writers)
            }
            if (read(file).stream().anyMatch(l -> l.startsWith("import jakarta.servlet.") || l.startsWith("import javax.servlet."))) {
                offenders.add(name);
            }
        }
        assertThat(offenders)
                .as("HTTP request/response types must not leak into business services (they could not be reused behind an event or a queue)")
                .isEmpty();
    }

    @Test
    void servicesDoNotUseWebAnnotationsOrResponseEntity() {
        List<String> offenders = new ArrayList<>();
        for (Path file : ModuleSources.javaFiles()) {
            String name = file.getFileName().toString();
            if (!name.matches(".*(Service|Policy|Directory|Payments|Dispatch|Matching|Operations)\\.java")) {
                continue;
            }
            if (read(file).stream().anyMatch(l -> l.matches("^import (org\\.springframework\\.web\\.bind\\.annotation|org\\.springframework\\.http\\.ResponseEntity).*"))) {
                offenders.add(ModuleSources.moduleOf(file) + "/" + name);
            }
        }
        assertThat(offenders).as("Business services return domain values; HTTP shaping belongs to the controller").isEmpty();
    }

    // ------------------------------------------------------------------ data ownership

    /**
     * A foreign key between tables of two different owners welds two domains at the database level: neither can move
     * to its own database while it exists. Existing ones are recorded; a new one needs a deliberate decision
     * (usually: store the id without a constraint and validate through the owner's contract).
     */
    @Test
    void noNewCrossOwnerForeignKeys() {
        Set<String> actual = new TreeSet<>();
        try (Stream<Path> files = Files.list(Path.of("src/main/resources/db/migration"))) {
            for (Path sql : files.filter(p -> p.toString().endsWith(".sql")).sorted().toList()) {
                collectForeignKeys(String.join("\n", read(sql)), actual);
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        if (Boolean.getBoolean("kunde.architecture.updateKnown")) {
            write(KNOWN_FKS, "Foreign keys between tables of different owners (ratchet, ArchitectureFitnessTest)."
                    + " Format: <table> -> <referenced table> (<owner> -> <owner>). Delete a line when the constraint is dropped.", actual);
        }
        Set<String> known = lines(KNOWN_FKS);

        Set<String> added = new TreeSet<>(actual);
        added.removeAll(known);
        Set<String> gone = new TreeSet<>(known);
        gone.removeAll(actual);
        assertThat(added)
                .as("New foreign key across table owners. Reference by id without a constraint and check through the owner's contract, "
                        + "or record the decision in src/test/resources" + KNOWN_FKS)
                .isEmpty();
        assertThat(gone).as("Foreign key no longer exists - delete it from src/test/resources" + KNOWN_FKS).isEmpty();
    }

    // ------------------------------------------------------------------ extraction helpers

    static Set<String> foreignKeysForDocs() {
        Set<String> out = new TreeSet<>();
        try (Stream<Path> files = Files.list(Path.of("src/main/resources/db/migration"))) {
            for (Path sql : files.filter(p -> p.toString().endsWith(".sql")).sorted().toList()) {
                collectForeignKeys(String.join("\n", read(sql)), out);
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return out;
    }

    private static void collectForeignKeys(String sql, Set<String> out) {
        String text = stripComments(sql);
        // statements are split on ';' - good enough for the migration style used here (no procedural blocks with FKs)
        for (String statement : text.split(";")) {
            String owningTable = null;
            Matcher create = CREATE_TABLE.matcher(statement);
            Matcher alter = ALTER_TABLE.matcher(statement);
            if (create.find()) {
                owningTable = create.group(1).toLowerCase();
            } else if (alter.find()) {
                owningTable = alter.group(1).toLowerCase();
            }
            if (owningTable == null) {
                continue;
            }
            Matcher ref = FK.matcher(statement);
            while (ref.find()) {
                String target = ref.group(1).toLowerCase();
                String from = ArchitectureBoundariesTest.ownerOf(owningTable);
                String to = ArchitectureBoundariesTest.ownerOf(target);
                if (from != null && to != null && !from.equals(to)) {
                    out.add(owningTable + " -> " + target + " (" + from + " -> " + to + ")");
                }
            }
        }
    }

    private static String stripComments(String sql) {
        return sql.replaceAll("(?m)--.*$", "").replaceAll("(?s)/\\*.*?\\*/", "");
    }

    // ------------------------------------------------------------------ graphs

    private static Map<String, Set<String>> gradleGraph() {
        Map<String, Set<String>> graph = new TreeMap<>();
        List<Path> buildFiles = new ArrayList<>();
        Path platform = BACKEND.resolve("platform/build.gradle.kts");
        if (Files.exists(platform)) {
            buildFiles.add(platform);
        }
        try (Stream<Path> services = Files.list(BACKEND.resolve("services"))) {
            services.sorted().map(s -> s.resolve("build.gradle.kts")).filter(Files::exists).forEach(buildFiles::add);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        for (Path build : buildFiles) {
            Path dir = build.getParent();
            String module = dir.getFileName().toString().equals("platform") ? ":platform" : ":services:" + dir.getFileName();
            Set<String> deps = new TreeSet<>();
            for (String line : read(build)) {
                if (line.trim().startsWith("//")) {
                    continue;
                }
                Matcher m = GRADLE_PROJECT.matcher(line);
                while (m.find()) {
                    deps.add(":" + m.group(1));
                }
            }
            graph.put(module, deps);
        }
        return graph;
    }

    /** Business-module coupling graph from real sources: imports plus SQL against foreign-owned tables. */
    private static Map<String, Set<String>> couplingGraph() {
        Map<String, Set<String>> graph = new TreeMap<>();
        Set<String> all = new TreeSet<>(ArchitectureBoundariesTest.importCoupling());
        all.addAll(ArchitectureBoundariesTest.sqlCoupling());
        for (String edge : all) {
            Matcher imp = IMPORT_EDGE.matcher(edge);
            Matcher sql = SQL_EDGE.matcher(edge);
            String from;
            String to;
            if (imp.find()) {
                from = imp.group(1);
                to = imp.group(2);
            } else if (sql.find()) {
                from = sql.group(1);
                to = sql.group(2);
            } else {
                continue;
            }
            if (from.equals("platform") || to.equals("platform") || from.equals("config")) {
                continue;
            }
            graph.computeIfAbsent(from, k -> new TreeSet<>()).add(to);
            graph.computeIfAbsent(to, k -> new TreeSet<>());
        }
        return graph;
    }

    /** Edges whose both ends are in the same strongly connected component. */
    static Set<String> edgesInsideCycles(Map<String, Set<String>> graph) {
        Map<String, String> component = new HashMap<>();
        for (String scc : stronglyConnected(graph)) {
            for (String node : scc.split(",")) {
                component.put(node, scc);
            }
        }
        Set<String> edges = new TreeSet<>();
        graph.forEach((from, targets) -> {
            for (String to : targets) {
                if (component.containsKey(from) && component.get(from).equals(component.get(to))) {
                    edges.add(from + " -> " + to);
                }
            }
        });
        return edges;
    }

    private static void write(String resource, String header, Set<String> lines) {
        List<String> out = new ArrayList<>();
        out.add("# " + header);
        out.addAll(lines);
        try {
            Files.write(Path.of("src/test/resources" + resource), out);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Tarjan; returns each strongly connected component with more than one node as "a,b,c" (sorted). */
    static Collection<String> stronglyConnected(Map<String, Set<String>> graph) {
        Map<String, Integer> index = new HashMap<>();
        Map<String, Integer> low = new HashMap<>();
        Deque<String> stack = new ArrayDeque<>();
        Set<String> onStack = new TreeSet<>();
        List<String> result = new ArrayList<>();
        int[] counter = {0};
        for (String node : graph.keySet()) {
            if (!index.containsKey(node)) {
                connect(node, graph, index, low, stack, onStack, counter, result);
            }
        }
        return result;
    }

    private static void connect(String v, Map<String, Set<String>> graph, Map<String, Integer> index, Map<String, Integer> low,
                                Deque<String> stack, Set<String> onStack, int[] counter, List<String> result) {
        index.put(v, counter[0]);
        low.put(v, counter[0]);
        counter[0]++;
        stack.push(v);
        onStack.add(v);
        for (String w : graph.getOrDefault(v, Set.of())) {
            if (!index.containsKey(w)) {
                connect(w, graph, index, low, stack, onStack, counter, result);
                low.put(v, Math.min(low.get(v), low.get(w)));
            } else if (onStack.contains(w)) {
                low.put(v, Math.min(low.get(v), index.get(w)));
            }
        }
        if (low.get(v).equals(index.get(v))) {
            TreeSet<String> component = new TreeSet<>();
            String w;
            do {
                w = stack.pop();
                onStack.remove(w);
                component.add(w);
            } while (!w.equals(v));
            if (component.size() > 1) {
                result.add(String.join(",", component));
            }
        }
    }

    // ------------------------------------------------------------------ io

    private static List<String> read(Path file) {
        try {
            return Files.readAllLines(file);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static Set<String> lines(String resource) {
        try (var in = ArchitectureFitnessTest.class.getResourceAsStream(resource)) {
            if (in == null) {
                throw new IllegalStateException("Missing test resource " + resource);
            }
            Set<String> out = new TreeSet<>();
            new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).lines()
                    .map(String::trim).filter(l -> !l.isEmpty() && !l.startsWith("#")).forEach(out::add);
            return out;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
