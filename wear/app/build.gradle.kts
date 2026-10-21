import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The phone app's upload key (android/key.properties, not in git). The Data
// Layer only pairs the watch app with the phone app when both have the same
// applicationId AND the same signing certificate.
val keyProperties = Properties()
val keyPropertiesFile = rootDir.resolve("../android/key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}
val hasReleaseKey = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    .all { !keyProperties.getProperty(it).isNullOrBlank() }
// tool\build.ps1 release sets this: a published watch APK must carry the
// phone's key, never the debug fallback.
if (System.getenv("REQUIRE_RELEASE_KEY") == "1" && !hasReleaseKey) {
    throw GradleException("REQUIRE_RELEASE_KEY=1 but android/key.properties is missing or incomplete")
}

// x.y.z from the phone's pubspec.yaml (`version: x.y.z+build`), unless the
// build passes -PversionName.
val pubspecVersion: String = run {
    val pubspec = rootDir.resolve("../pubspec.yaml")
    val line = if (pubspec.exists()) {
        pubspec.readLines().firstOrNull { it.trim().startsWith("version:") }
    } else {
        null
    }
    line?.substringAfter("version:")?.trim()?.substringBefore("+")?.ifBlank { null } ?: "0.0.0"
}

android {
    namespace = "com.mfficiency.best_todo_2.wear"
    compileSdk = 36

    defaultConfig {
        // Exactly the phone app's applicationId (see above).
        applicationId = "com.mfficiency.best_todo_2"
        minSdk = 30
        targetSdk = 34
        versionCode = (findProperty("buildNumber") ?: System.getenv("BUILD_NUMBER") ?: "1")
            .toString().trim().toInt()
        versionName = (findProperty("versionName") ?: pubspecVersion).toString()
    }

    signingConfigs {
        // Without the release key: the phone's committed debug keystore (the
        // one its own release build falls back to), so two such local builds
        // still pair with each other.
        getByName("debug") {
            storeFile = rootDir.resolve("../android/app/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                // The phone resolves storeFile against android/app (its app
                // module's file()); File.resolve keeps an absolute path as is.
                storeFile = rootDir.resolve("../android/app")
                    .resolve(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("androidx.wear.compose:compose-navigation:1.4.1")
    implementation("androidx.compose.material:material-icons-core:1.7.6")
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
