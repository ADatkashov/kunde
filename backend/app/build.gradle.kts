plugins {
    `java-library`
    alias(libs.plugins.springBoot)
}

apply(from = rootProject.file("gradle/kunde-module.gradle.kts"))

dependencies {
    implementation(project(":platform"))
    implementation(project(":services:admin"))
    implementation(project(":services:support"))
    implementation(project(":services:education"))
    implementation(project(":services:flowers"))
    implementation(project(":services:events"))
    implementation(project(":services:leisure"))
    implementation(project(":services:delivery"))
    implementation(project(":services:maps"))
    implementation(project(":services:rides"))
    implementation(project(":services:auto"))
    implementation(project(":services:health"))
    implementation(project(":services:homeservices"))
    implementation(project(":services:beauty"))
    implementation(project(":services:booking"))
    implementation(project(":services:groceries"))
    implementation(project(":services:food"))
    implementation(project(":services:partners"))
    implementation(project(":services:identity"))
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
