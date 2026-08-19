plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH").orEmpty()
val releaseKeystorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD").orEmpty()
val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS").orEmpty()
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD").orEmpty()
val hasReleaseSigning = releaseKeystorePath.isNotBlank()
        && releaseKeystorePassword.isNotBlank()
        && releaseKeyAlias.isNotBlank()
        && releaseKeyPassword.isNotBlank()
        && file(releaseKeystorePath).isFile
val allowDebugSigning = System.getenv("ALLOW_DEBUG_SIGNING") == "true"

android {
    namespace = "com.axion.pqc"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.axion.pqc"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugSigning) {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

if (hasReleaseSigning) {
    android.signingConfigs {
        create("release") {
            storeFile = file(releaseKeystorePath)
            storePassword = releaseKeystorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }
}

// Debug builds remain usable without private release material. Any release
// task must explicitly provide a keystore or opt into debug signing for local
// testing; production builds can never silently use the debug key.
gradle.taskGraph.whenReady {
    val releaseTaskRequested = allTasks.any { it.name.contains("Release", ignoreCase = true) }
    if (releaseTaskRequested && !hasReleaseSigning && !allowDebugSigning) {
        throw GradleException(
            "Release signing is not configured. Set ANDROID_KEYSTORE_PATH, "
                    + "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and "
                    + "ANDROID_KEY_PASSWORD, or set ALLOW_DEBUG_SIGNING=true "
                    + "only for local testing."
        )
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
