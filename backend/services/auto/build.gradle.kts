plugins {
    `java-library`
}

apply(from = rootProject.file("gradle/kunde-module.gradle.kts"))

dependencies {
    implementation(project(":platform"))
    api(project(":services:booking"))  // AutoPayments implements booking.BookingPayments: the supertype is part of the public API
    implementation(project(":services:identity"))
}
