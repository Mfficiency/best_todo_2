// BestToDo's Wear OS companion: a standalone Gradle build, never included in
// android/settings.gradle.kts (the phone's `flutter build apk` doesn't see it).
// See README.md.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "best_todo-wear"
include(":app")
