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
        // Xposed Bridge API stubs (compileOnly).
        maven { url = uri("https://api.xposed.info/") }
        // Fallback for the same artifact if the above is unreachable:
        // maven { url = uri("https://jitpack.io") }
    }
}

rootProject.name = "MockLocationHelper"
include(":app")
