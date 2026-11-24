// Root project: aggregate tasks only; modules are configured by the convention plugin in buildSrc.
plugins {
    base
    // Applied to modules by gradle/kunde-module.gradle.kts; declared here once so every module sees the same plugin classpath.
    alias(libs.plugins.springBoot) apply false
}

group = "kz.kunde"
version = "0.1.0-SNAPSHOT"

// Resolved dependency graph (runtime + test) in the shape the security baseline reads: {groupId, artifactId, version, children}.
// scripts/ci/osv_audit.py and security_baseline.py consume it; usage: ./gradlew dependencyTreeJson -PtreeOutput=../reports/maven.json
tasks.register("dependencyTreeJson") {
    group = "verification"
    description = "Writes the resolved dependency tree as JSON for the OSV audit"
    doLast {
        // Project modules (group kz.kunde) are our own code, not third-party components: their dependencies are lifted up.
        fun nodes(d: ResolvedDependency): List<String> =
            if (d.moduleGroup == "kz.kunde") d.children.sortedBy { it.name }.flatMap { nodes(it) }
            else listOf("{\"groupId\":\"${d.moduleGroup}\",\"artifactId\":\"${d.moduleName}\",\"version\":\"${d.moduleVersion}\"," +
                "\"children\":[${d.children.sortedBy { it.name }.flatMap { nodes(it) }.joinToString(",")}]}")
        val roots = project(":app").configurations.getByName("testRuntimeClasspath").resolvedConfiguration.firstLevelModuleDependencies
        val json = "{\"groupId\":\"${project.group}\",\"artifactId\":\"${project.name}\",\"version\":\"${project.version}\"," +
            "\"children\":[${roots.sortedBy { it.name }.flatMap { nodes(it) }.joinToString(",")}]}"
        val out = file(providers.gradleProperty("treeOutput").orElse("build/reports/dependency-tree.json").get())
        out.parentFile.mkdirs()
        out.writeText(json + "\n")
    }
}
