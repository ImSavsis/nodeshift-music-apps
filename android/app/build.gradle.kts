plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val buildNumber = (System.getenv("NSM_BUILD") ?: "1").toInt()

android {
    namespace = "space.nodeshift.music"
    compileSdk = 36

    defaultConfig {
        applicationId = "space.nodeshift.music"
        minSdk = 26
        targetSdk = 36
        versionCode = buildNumber
        versionName = "0.1.0"
    }

    signingConfigs {
        val path = System.getenv("NSM_KEYSTORE")
        if (path != null && file(path).exists()) {
            create("release") {
                storeFile = file(path)
                storePassword = System.getenv("NSM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("NSM_KEY_ALIAS")
                keyPassword = System.getenv("NSM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("main") {
            assets.srcDir(rootProject.file("../shared/fonts"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
        jniLibs.useLegacyPackaging = false
    }
}

kotlin {
    jvmToolchain(17)
}

configurations.all {
    resolutionStrategy {
        force(
            "androidx.core:core:1.18.0",
            "androidx.core:core-ktx:1.18.0",
            "androidx.lifecycle:lifecycle-runtime-compose:2.10.0",
        )
    }
}

dependencies {
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.browser:browser:1.10.0")
    implementation("androidx.documentfile:documentfile:1.1.0")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-session:1.11.1")
    implementation("com.squareup.okhttp3:okhttp:5.5.0")
    implementation("io.github.kyant0:taglib:1.0.6")
    implementation("org.apache.commons:commons-compress:1.28.0")
    implementation("org.tukaani:xz:1.12")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
}
