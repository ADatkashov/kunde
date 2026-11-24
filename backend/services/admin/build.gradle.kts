plugins {
    `java-library`
}

apply(from = rootProject.file("gradle/kunde-module.gradle.kts"))

dependencies {
    implementation(project(":platform"))
    implementation(project(":services:auto"))
    implementation(project(":services:delivery"))
    implementation(project(":services:food"))
    implementation(project(":services:identity"))
    implementation(project(":services:leisure"))
    implementation(project(":services:partners"))
}
