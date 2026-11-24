plugins {
    java
    alias(libs.plugins.springBoot)
    alias(libs.plugins.dependencyManagement)
}

group = "kz.kunde"
version = "0.1.0-SNAPSHOT"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-security-oauth2-resource-server")
    implementation("org.springframework.boot:spring-boot-starter-jdbc")
    implementation("org.springframework.boot:spring-boot-starter-flyway")
    implementation("org.flywaydb:flyway-database-postgresql")
    runtimeOnly("org.postgresql:postgresql")
    implementation(libs.pdfbox)
    implementation("org.springframework.boot:spring-boot-jackson2")

    testImplementation("org.springframework.boot:spring-boot-starter-webmvc-test")
    testImplementation("org.springframework.boot:spring-boot-resttestclient")
    testImplementation("org.springframework.boot:spring-boot-restclient")
    testImplementation("org.springframework.boot:spring-boot-starter-security-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

// Spring MVC resolves @PathVariable/@RequestParam names by reflection; spring-boot-starter-parent does the same for Maven.
tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-parameters")
    options.encoding = "UTF-8"
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    // The architecture ratchet rewrites its baseline on request (-Dkunde.architecture.updateBaseline=true).
    systemProperty("kunde.architecture.updateBaseline", System.getProperty("kunde.architecture.updateBaseline") ?: "false")
}

tasks.bootJar {
    archiveFileName = "kunde-api-${project.version}.jar"
}

// Resolved dependency graph (runtime + test) in the shape the security baseline reads: {groupId, artifactId, version, children}.
// scripts/ci/osv_audit.py and security_baseline.py consume it; usage: ./gradlew dependencyTreeJson -PtreeOutput=../reports/maven.json
tasks.register("dependencyTreeJson") {
    group = "verification"
    description = "Writes the resolved dependency tree as JSON for the OSV audit"
    doLast {
        fun node(d: ResolvedDependency): String =
            "{\"groupId\":\"${d.moduleGroup}\",\"artifactId\":\"${d.moduleName}\",\"version\":\"${d.moduleVersion}\"," +
                "\"children\":[${d.children.sortedBy { it.name }.joinToString(",") { node(it) }}]}"
        val roots = configurations.getByName("testRuntimeClasspath").resolvedConfiguration.firstLevelModuleDependencies
        val json = "{\"groupId\":\"${project.group}\",\"artifactId\":\"${project.name}\",\"version\":\"${project.version}\"," +
            "\"children\":[${roots.sortedBy { it.name }.joinToString(",") { node(it) }}]}"
        val out = file(providers.gradleProperty("treeOutput").orElse("build/reports/dependency-tree.json").get())
        out.parentFile.mkdirs()
        out.writeText(json + "\n")
    }
}
