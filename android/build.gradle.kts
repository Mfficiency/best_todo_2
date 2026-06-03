allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // The home_widget plugin pulls androidx.glance via a dynamic version,
    // which now resolves to a 2026 alpha (glance-appwidget:1.3.0-alpha01)
    // that requires compileSdk 37 and Android Gradle Plugin 9.1.0+. Pin
    // Glance back to the latest stable release so the build works with the
    // project's AGP 8.9.1 / compileSdk setup.
    configurations.all {
        resolutionStrategy {
            force("androidx.glance:glance:1.1.1")
            force("androidx.glance:glance-appwidget:1.1.1")
            force("androidx.glance:glance-material3:1.1.1")
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
