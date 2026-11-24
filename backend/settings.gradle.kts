pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

// Gradle build of the KUNDE backend (ADR-023). Step 1: the existing single module built by Gradle, equivalent to pom.xml.
// Domain modules (services/*) and platform are carved out of it in later PRs; Maven stays the source of truth for CI until
// the equivalence gate in ADR-023 passes.
rootProject.name = "kunde-api"
