plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.headless.mockloc"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.headless.mockloc"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "0.1"
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    // The LSPosed loader looks for these inside the APK at META-INF/xposed/.
    // We place them in src/main/resources/META-INF/xposed/ — AGP includes Java
    // resources into the APK at the same path. Make sure nothing strips them.
    packaging {
        resources {
            // do NOT exclude META-INF/xposed
            excludes += setOf("META-INF/AL2.0", "META-INF/LGPL2.1")
        }
    }
}

dependencies {
    // Hooks run inside the target process; the API is supplied at runtime by LSPosed.
    compileOnly("de.robv.android.xposed:api:82")
}
