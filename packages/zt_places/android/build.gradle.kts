// Plain Java on purpose: builds the same in apps on Android Gradle Plugin 8
// (separate Kotlin plugin) and 9 (built-in Kotlin). No dependencies beyond
// the Android SDK, so nothing from Google Play services is pulled in.
group = "dev.sagron.zt_places"
version = "1.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.7.3")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.sagron.zt_places"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}
