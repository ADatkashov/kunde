package kz.kunde.architecture;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

/**
 * Production sources of every backend module. The architecture tests run in the {@code :app} project and must see
 * {@code platform/} and every {@code services/*} module too; a module root is {@code <module>/src/main/java/kz/kunde}.
 */
final class ModuleSources {
    private static final String ROOT = "src/main/java/kz/kunde";

    private ModuleSources() {}

    /** The {@code kz/kunde} source roots: this project and its sibling modules (backend/platform, backend/services/*). */
    static List<Path> roots() {
        Path backend = Path.of("..").normalize();
        List<Path> roots = new ArrayList<>();
        roots.add(Path.of(ROOT));
        try (Stream<Path> top = Files.list(backend)) {
            for (Path dir : top.sorted().toList()) {
                Path name = dir.getFileName();
                if (name.toString().equals("app")) {
                    continue;
                }
                if (name.toString().equals("services")) {
                    try (Stream<Path> services = Files.list(dir)) {
                        services.sorted().map(s -> s.resolve(ROOT)).filter(Files::isDirectory).forEach(roots::add);
                    }
                } else if (Files.isDirectory(dir.resolve(ROOT))) {
                    roots.add(dir.resolve(ROOT));
                }
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return roots;
    }

    static List<Path> javaFiles() {
        List<Path> files = new ArrayList<>();
        for (Path root : roots()) {
            try (Stream<Path> walk = Files.walk(root)) {
                walk.filter(p -> p.toString().endsWith(".java")).forEach(files::add);
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        }
        files.sort(null);
        return files;
    }

    /** The first package segment under {@code kz.kunde} (the business module or {@code platform}). */
    static String moduleOf(Path file) {
        Path normalized = file.normalize();
        for (Path root : roots()) {
            if (normalized.startsWith(root.normalize())) {
                return root.normalize().relativize(normalized).getName(0).toString();
            }
        }
        throw new IllegalArgumentException(file.toString());
    }
}
