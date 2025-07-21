plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.newton"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        // Enable core library desugaring here - Kotlin DSL syntax
        isCoreLibraryDesugaringEnabled = true // <--- CORRECTED SYNTAX
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8.toString() // Set JVM target to 1.8 for Kotlin
    }

    defaultConfig {
        applicationId = "com.example.newton"
        minSdk = 21
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Add the core library desugaring dependency - Kotlin DSL syntax
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") // <--- CORRECTED SYNTAX
}