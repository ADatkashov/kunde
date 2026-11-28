plugins {
    `java-library`
}

apply(from = rootProject.file("gradle/kunde-module.gradle.kts"))

dependencies {
    implementation(project(":platform"))
    implementation(project(":services:booking"))
    implementation("software.amazon.awssdk:s3:2.32.29")
}
