import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}


val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseKeystore = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    .all { !keystoreProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.mfficiency.best_todo_2"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mfficiency.best_todo_2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // androidx.work (pulled in transitively via glance/home_widget)
        // requires a minSdk of at least 23.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasReleaseKeystore) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    // Use a committed, fixed debug keystore (standard public debug
    // credentials) instead of the per-machine/per-CI-run ~/.android
    // keystore, so every build is signed with the same key and updates
    // install in place. The release build falls back to this signing
    // config until a real release keystore (key.properties) is provided.
    signingConfigs {
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            // Keep rules for Gson/flutter_local_notifications — without them
            // R8 strips generic signatures and every alarm schedule call
            // fails at runtime with "Missing type parameter." (release only).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

afterEvaluate {
    val createVersionedReleaseApk = tasks.register("createVersionedReleaseApk") {
        doLast {
            // Full pubspec version: x.y.z+build (e.g. 0.1.117+87). versionName carries
            // x.y.z, versionCode the build number, so recombine them.
            val fullVersion =
                "${(flutter.versionName ?: "0.0.0").substringBefore("+")}+${flutter.versionCode}"

            // versionCode 1 means pubspec lost its `+build` suffix: the APK would be
            // rejected as a downgrade on any device holding an earlier build.
            if (flutter.versionCode == 1) {
                logger.warn(
                    "[apk-rename] WARNING: versionCode is 1 — pubspec.yaml `version:` is " +
                        "missing its +build suffix. Fix it before shipping this APK."
                )
            }

            val apkCandidates = listOf(
                rootProject.layout.buildDirectory.file("app/outputs/flutter-apk/app-release.apk").get().asFile,
                rootProject.layout.buildDirectory.file("app/outputs/apk/release/app-release.apk").get().asFile,
                layout.buildDirectory.file("outputs/apk/release/app-release.apk").get().asFile,
            )

            val sourceApk = apkCandidates.firstOrNull { it.exists() }
            logger.lifecycle("[apk-rename] Looking for release APK. Checked: ${apkCandidates.joinToString { it.path }}")

            if (sourceApk == null) {
                logger.lifecycle("[apk-rename] No release APK found, skipping rename.")
                return@doLast
            }

            val renamedApk = File(sourceApk.parentFile, "best_todo_${fullVersion}.apk")
            sourceApk.copyTo(renamedApk, overwrite = true)
            logger.lifecycle("[apk-rename] Created ${renamedApk.path}")
        }
    }

    tasks.matching { it.name in setOf("assembleRelease", "copyReleaseApk", "packageRelease") }.configureEach {
        finalizedBy(createVersionedReleaseApk)
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.7.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.10.3")
    testImplementation("androidx.test:core:1.5.0")
}

// home_widget 0.8.1 declares `androidx.glance:glance-appwidget:1.+`, which now
// resolves to 1.3.0-alpha01 and demands compileSdk 37 + AGP 9.1.0. Pin to the
// latest stable 1.1.x until we're ready to bump the Android toolchain.
//
// Same story one level down, and it broke the release build on 2026-08-15:
// WorkManager came in unpinned and picked up the freshly published
// `androidx.work:work-runtime-ktx:2.12.0-rc01`, which declares minSdk 24 —
// the manifest merger then refused this app's minSdk 23 and every
// `assembleRelease` failed at `:app:processReleaseMainManifest`, with no code
// change of ours involved. Pinned to the last line that still supports 23, so
// a new upstream pre-release can't take the build out again. Raising minSdk to
// 24 would also fix it, but that drops Android 6 devices — a product decision,
// not a build fix.
configurations.all {
    resolutionStrategy {
        force("androidx.glance:glance-appwidget:1.1.1")
        force("androidx.glance:glance:1.1.1")
        force("androidx.work:work-runtime:2.10.0")
        force("androidx.work:work-runtime-ktx:2.10.0")
    }
}
