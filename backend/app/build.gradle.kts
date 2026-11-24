plugins {
    `java-library`
    alias(libs.plugins.springBoot)
}

apply(from = rootProject.file("gradle/kunde-module.gradle.kts"))

dependencies {
    implementation(project(":platform"))
    implementation("org.springframework.boot:spring-boot-starter-flyway")
    implementation("org.flywaydb:flyway-database-postgresql")
    runtimeOnly("org.postgresql:postgresql")
    implementation(libs.pdfbox)

    testImplementation("org.springframework.boot:spring-boot-resttestclient")
    testImplementation("org.springframework.boot:spring-boot-restclient")
}

// The executable keeps its historical name and location (backend/build/libs) so CI scripts and the Dockerfile stay valid.
tasks.bootJar {
    archiveFileName = "kunde-api-${project.version}.jar"
    destinationDirectory = rootProject.layout.buildDirectory.dir("libs")
}

// Spring Boot's plain jar of :app is not shipped.
tasks.jar {
    enabled = false
}
