allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { androidExtension ->
            when (androidExtension) {
                is com.android.build.gradle.AppExtension -> {
                    androidExtension.compileSdkVersion(36)
                    androidExtension.ndkVersion = "29.0.14206865"
                }
                is com.android.build.gradle.LibraryExtension -> {
                    androidExtension.compileSdkVersion(36)
                    androidExtension.ndkVersion = "29.0.14206865"
                }
            }
        }
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
