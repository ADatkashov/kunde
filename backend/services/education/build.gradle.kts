plugins {
    `java-library`
}

apply(from = rootProject.file("gradle/kunde-module.gradle.kts"))

dependencies {
    implementation(project(":platform"))
    implementation(project(":services:identity"))
    implementation(project(":services:partners"))
    implementation(libs.pdfbox)
}
