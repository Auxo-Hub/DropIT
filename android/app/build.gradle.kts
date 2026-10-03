plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.dropit.phone"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.dropit.phone"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

// Deliberately dependency-free: the HTTP server, SAF bridge and discovery are all
// implemented on the Android framework so the APK stays tiny and the build fast.
dependencies {
}
