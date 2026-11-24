pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

// KUNDE backend (ADR-023): one Spring Boot application (:app) assembled from library modules.
//   :platform  technical kernel (security filters, errors, feature gates, geo/placement/events contracts)
//   :app       composition root, Flyway migrations and the business domains not yet carved into modules
// Business domains move to services/<domain> in small steps; the executable stays :app.
rootProject.name = "kunde-api"

include(":platform", ":app", ":services:identity", ":services:partners", ":services:food", ":services:groceries", ":services:booking", ":services:beauty", ":services:homeservices", ":services:health", ":services:auto", ":services:rides", ":services:maps", ":services:delivery", ":services:leisure", ":services:events", ":services:education", ":services:support", ":services:admin")
