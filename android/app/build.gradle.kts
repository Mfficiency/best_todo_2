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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

afterEvaluate {
    val createVersionedReleaseApk = tasks.register("createVersionedReleaseApk") {
        doLast {
            // versionName from pubspec: x.y.z+build -> keep z (e.g. 0.1.57+27 -> 57)
            val suffix = (flutter.versionName ?: "0.0.0")
                .substringBefore("+")
                .substringAfterLast(".")

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

            val renamedApk = File(sourceApk.parentFile, "${sourceApk.nameWithoutExtension}_${suffix}.apk")
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
configurations.all {
    resolutionStrategy {
        force("androidx.glance:glance-appwidget:1.1.1")
        force("androidx.glance:glance:1.1.1")
    }
}
