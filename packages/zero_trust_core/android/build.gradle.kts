// Android part of zero_trust_core: "Sign in once per phone" (S-2). Plain
// Java, so it builds the same with every app's Android Gradle Plugin and
// Kotlin setup.
group = "bz.zerotrust.core"
version = "1.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.12.1")
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
    namespace = "bz.zerotrust.core"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 21
    }
}
