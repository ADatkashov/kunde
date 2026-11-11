// AGP9 has a runtime KGP dependency. Align actual buildscript classpaths,
// not only plugin-management declarations, to the supported patched version.
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.20")
        // TASK-046: security maintenance constraints are buildscript-only.
        // Keep the complete Bouncy Castle family on the same patched release.
        constraints {
            add("classpath", "org.bouncycastle:bcprov-jdk18on:1.85.2")
            add("classpath", "org.bouncycastle:bcpkix-jdk18on:1.85.2")
            add("classpath", "org.bouncycastle:bcutil-jdk18on:1.85.2")
            add("classpath", "com.google.guava:guava:33.7.2-jre")
            add("classpath", "org.apache.commons:commons-lang3:3.18.0")
            add("classpath", "org.bitbucket.b_c:jose4j:0.9.6")
            add("classpath", "org.jdom:jdom2:2.0.6.1")
        }
    }
}
subprojects {
    buildscript {
        repositories { google(); mavenCentral() }
        dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.20")
        // TASK-046: security maintenance constraints are buildscript-only.
        // Keep the complete Bouncy Castle family on the same patched release.
        constraints {
            add("classpath", "org.bouncycastle:bcprov-jdk18on:1.85.2")
            add("classpath", "org.bouncycastle:bcpkix-jdk18on:1.85.2")
            add("classpath", "org.bouncycastle:bcutil-jdk18on:1.85.2")
            add("classpath", "com.google.guava:guava:33.7.2-jre")
            add("classpath", "org.apache.commons:commons-lang3:3.18.0")
            add("classpath", "org.bitbucket.b_c:jose4j:0.9.6")
            add("classpath", "org.jdom:jdom2:2.0.6.1")
        }
    }
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
