import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real release signing, read from android/key.properties (gitignored — see
// the repo root .gitignore — since it points at a keystore file and its
// passwords, neither of which belong in version control). That file doesn't
// exist in a fresh checkout, so this falls back to debug signing rather than
// failing the build — `flutter run --release` and CI builds that never
// upload to Play still work with no setup. Generate your own keystore with
// `keytool -genkey -v -keystore <path-outside-the-repo>/upload-keystore.jks
// -keyalg RSA -keysize 2048 -validity 10000 -alias upload`, then create
// android/key.properties with:
//   storePassword=<password>
//   keyPassword=<password>
//   keyAlias=upload
//   storeFile=<absolute path to the .jks file>
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.playmyset.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.playmyset.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // A Play upload needs the "release" config above; anything built
            // without key.properties present (local `flutter run --release`,
            // CI that isn't publishing) still signs with the debug key so it
            // keeps working with zero setup.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
