plugins {
    `java-library`
}

apply(from = rootProject.file("gradle/kunde-module.gradle.kts"))

// The kernel is a library: Spring types appear in its public signatures, so the starters are exposed with api.
dependencies {
    api("org.springframework.boot:spring-boot-starter-webmvc")
    api("org.springframework.boot:spring-boot-starter-validation")
    api("org.springframework.boot:spring-boot-starter-actuator")
    api("org.springframework.boot:spring-boot-starter-security")
    api("org.springframework.boot:spring-boot-starter-security-oauth2-resource-server")
    api("org.springframework.boot:spring-boot-starter-jdbc")
    api("org.springframework.boot:spring-boot-jackson2")
}
