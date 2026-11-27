// Shared configuration of every backend module (platform, services/*, app): Java 21, Spring Boot BOM, JUnit 5, -parameters.
// A script plugin, applied with `apply(from = rootProject.file("gradle/kunde-module.gradle.kts"))`; it avoids a buildSrc build
// (and its Kotlin toolchain downloads) while the module count is small. It can become a convention plugin in build-logic later.
// The module declares plugins { `java-library` } itself so that type-safe accessors exist.

group = "kz.kunde"
version = "0.1.0-SNAPSHOT"

extensions.configure<JavaPluginExtension> {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

val springBootVersion = extensions.getByType<VersionCatalogsExtension>().named("libs").findVersion("springBoot").get().requiredVersion

dependencies {
    // Spring Boot managed versions, enforced like the dependency-management plugin did (a higher transitive version must not win).
    val bom = enforcedPlatform("org.springframework.boot:spring-boot-dependencies:$springBootVersion")
    add("implementation", bom)
    add("testImplementation", bom)
    add("testImplementation", "org.springframework.boot:spring-boot-starter-webmvc-test")
    add("testImplementation", "org.springframework.boot:spring-boot-starter-security-test")
    add("testRuntimeOnly", "org.junit.platform:junit-platform-launcher")
}

// Spring MVC resolves @PathVariable/@RequestParam names by reflection.
tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-parameters")
    options.encoding = "UTF-8"
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    // Tests talk to PostgreSQL and the clock, which Gradle does not track as inputs: a cached "PASS" would be a lie. Never cache them.
    outputs.cacheIf("tests depend on external state (PostgreSQL, time)") { false }
    // `./gradlew test --tests X` is run across all modules; a module without a match must not fail the build.
    filter {
        isFailOnNoMatchingTests = false
    }
    // The architecture ratchet rewrites its baseline on request (-Dkunde.architecture.updateBaseline=true).
    systemProperty("kunde.architecture.updateBaseline", System.getProperty("kunde.architecture.updateBaseline") ?: "false")
    // Same for the fitness-function ratchets (known coupling cycles, cross-owner foreign keys).
    systemProperty("kunde.architecture.updateKnown", System.getProperty("kunde.architecture.updateKnown") ?: "false")
}
