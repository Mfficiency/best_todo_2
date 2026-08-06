allprojects {
    repositories {
        google()
        mavenCentral()
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

// home_widget 0.8.1 still compiles Kotlin at JVM target 1.8 while the androidx
// libraries it inlines now ship JVM 11 bytecode, so :home_widget:compileReleaseKotlin
// fails with "Cannot inline bytecode built with JVM target 11 into bytecode that
// is being built with JVM target 1.8" (every Build APK run since 2026-07-28).
// Align every plugin module with the app's JVM 11. afterEvaluate + configureEach
// so these win over whatever the plugin's own build script sets.
subprojects {
    val alignJvmTarget = {
        extensions.findByType<com.android.build.gradle.BaseExtension>()
            ?.compileOptions?.apply {
                sourceCompatibility = JavaVersion.VERSION_11
                targetCompatibility = JavaVersion.VERSION_11
            }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions.jvmTarget
                    .set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
    }
    // The evaluationDependsOn(":app") above force-evaluates :app before this
    // block runs, and afterEvaluate throws on an already-evaluated project —
    // configure those immediately instead.
    if (state.executed) alignJvmTarget() else afterEvaluate { alignJvmTarget() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
