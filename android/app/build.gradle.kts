plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing
//
// The upload keystore is NEVER in the repository. It comes from one of:
//   1. Codemagic: `environment.android_signing` in codemagic.yaml exports
//      CM_KEYSTORE_PATH / CM_KEYSTORE_PASSWORD / CM_KEY_ALIAS / CM_KEY_PASSWORD.
//   2. A local, git-ignored android/key.properties:
//        storeFile=<path to the .jks, absolute or relative to android/app>
//        storePassword=...
//        keyAlias=...
//        keyPassword=...
// If neither is present:
//   * on CI (the CI env var is set) any release build FAILS — it must never
//     quietly fall back to the debug key, which Google Play rejects;
//   * on a developer machine the debug key is used, so `flutter run --release`
//     still works.
// ---------------------------------------------------------------------------
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val ciEnvValue: String = System.getenv("CI") ?: ""
val isCiBuild: Boolean = ciEnvValue.isNotBlank() && !ciEnvValue.equals("false", ignoreCase = true)
val ciKeystorePath: String = System.getenv("CM_KEYSTORE_PATH") ?: ""
val localKeystorePath: String = keystoreProperties.getProperty("storeFile") ?: ""
val hasCiKeystore: Boolean = ciKeystorePath.isNotBlank()
val hasLocalKeystore: Boolean = localKeystorePath.isNotBlank()
val hasReleaseKeystore: Boolean = hasCiKeystore || hasLocalKeystore

android {
    namespace = "com.usengineering.trellis"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Must match the Play Console package, android/app/google-services.json
        // and the Firebase Android app. Do not change after the first upload.
        applicationId = "com.usengineering.trellis"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Flutter's defaults (minSdk 24 / target 36 / compile 36 on Flutter 3.47)
        // already satisfy every plugin floor in this app (highest floor: 24).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode / versionName come from pubspec.yaml's `version:` or from
        // `flutter build --build-number / --build-name` (what codemagic.yaml passes).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                if (hasCiKeystore) {
                    storeFile = file(ciKeystorePath)
                    storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                    keyAlias = System.getenv("CM_KEY_ALIAS")
                    keyPassword = System.getenv("CM_KEY_PASSWORD")
                } else {
                    storeFile = file(localKeystorePath)
                    storePassword = keystoreProperties.getProperty("storePassword")
                    keyAlias = keystoreProperties.getProperty("keyAlias")
                    keyPassword = keystoreProperties.getProperty("keyPassword")
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else if (isCiBuild) {
                    // No keystore on CI: leave the build unsigned here; the
                    // task-graph check below stops the build with a clear error.
                    null
                } else {
                    // Local convenience only (flutter run --release).
                    signingConfigs.getByName("debug")
                }
            // R8 code + resource shrinking is switched on for release by the
            // Flutter Gradle plugin. No app-level keep rules are needed: Firebase,
            // RevenueCat, PostHog and jni ship their own consumer rules. If one is
            // ever required, create android/app/proguard-rules.pro — Flutter picks
            // that file up automatically.
        }
    }
}

// Fail loudly, and early, when a CI release build has no upload keystore.
if (isCiBuild && !hasReleaseKeystore) {
    val appProjectPath = project.path
    // The tasks that produce a distributable release APK / app bundle.
    val releaseOutputTasks = setOf(
        "assembleRelease",
        "packageRelease",
        "bundleRelease",
        "packageReleaseBundle",
        "signReleaseBundle",
    )
    gradle.taskGraph.whenReady {
        val releaseTask = allTasks.firstOrNull { task ->
            task.path.startsWith("$appProjectPath:") && task.name in releaseOutputTasks
        }
        if (releaseTask != null) {
            throw GradleException(
                "Release signing is not configured for this CI build (task ${releaseTask.path}). " +
                    "CM_KEYSTORE_PATH is not set and android/key.properties has no storeFile. " +
                    "In Codemagic, upload the upload keystore under Team settings > codemagic.yaml " +
                    "settings > Code signing identities > Android keystores and reference it from " +
                    "environment.android_signing in codemagic.yaml. Refusing to sign a release " +
                    "build with the debug key."
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
