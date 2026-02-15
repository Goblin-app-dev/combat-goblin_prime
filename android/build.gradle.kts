allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Enable Gradle dependency locking for reproducible builds.
// Generate lockfiles: ./gradlew -PenableDependencyLocking=true dependencies --write-locks
// Once lockfiles are committed, you can remove this guard and make locking always-on.
val enableDependencyLocking = providers.gradleProperty("enableDependencyLocking")
    .map { it.equals("true", ignoreCase = true) }
    .orElse(false)

allprojects {
    if (enableDependencyLocking.get()) {
        dependencyLocking {
            lockAllConfigurations()
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
