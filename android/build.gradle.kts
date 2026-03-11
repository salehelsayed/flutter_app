import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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

subprojects {
    if (name == "app") {
        return@subprojects
    }

    plugins.withId("com.android.library") {
        // Eagerly set JVM 11 — works for plugins that don't override compileOptions.
        extensions.findByType(LibraryExtension::class.java)?.compileOptions {
            sourceCompatibility = JavaVersion.VERSION_11
            targetCompatibility = JavaVersion.VERSION_11
        }

        // afterEvaluate overrides plugins that hardcode JVM 1.8 in their own
        // build.gradle (e.g. bonsoir_android 5.x).  Some plugins (e.g.
        // audio_session) finalise compileOptions before afterEvaluate — the
        // try/catch lets those keep the eagerly-set JVM 11 while still fixing
        // plugins that don't finalise.  Kotlin JVM target is always synced to
        // match the resolved Java target so there is never a mismatch.
        afterEvaluate {
            val libExt = extensions.findByType(LibraryExtension::class.java)
                ?: return@afterEvaluate
            try {
                libExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_11
                libExt.compileOptions.targetCompatibility = JavaVersion.VERSION_11
            } catch (_: Exception) {
                // Already finalised — Java stays at the eagerly-set JVM 11.
            }
            tasks.withType<KotlinCompile>().configureEach {
                kotlinOptions {
                    jvmTarget = libExt.compileOptions.targetCompatibility.toString()
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
