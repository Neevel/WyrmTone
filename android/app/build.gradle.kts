import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Fail closed. Only two compile gates exist, both debug-only and false in release:
// ENABLE_MATRIBOX_P01_RAW_BACKUP enables the read-only preset reader/backup, and
// ENABLE_MATRIBOX_TONE_TRANSFER enables the productive transfer (P11..P99 only) together with
// the reader it depends on. The historical probe/certification gates were removed with their
// tools; an old define is simply ignored and enables nothing.
val decodedDartDefines = providers.gradleProperty("dart-defines").orNull?.split(",")
    ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull() }
    .orEmpty()
fun requestedDefine(name: String): Boolean =
    decodedDartDefines.count { it.startsWith("$name=") } == 1 &&
        decodedDartDefines.single { it.startsWith("$name=") } == "$name=true"
val requestedP01RawBackup = requestedDefine("ENABLE_MATRIBOX_P01_RAW_BACKUP")
val requestedToneTransfer = requestedDefine("ENABLE_MATRIBOX_TONE_TRANSFER")
val enableP01RawBackup = requestedP01RawBackup || requestedToneTransfer
val enableToneTransfer = requestedToneTransfer

android {
    buildFeatures { buildConfig = true }
    namespace = "de.neevel.wyrmtone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.neevel.wyrmtone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_RAW_BACKUP", enableP01RawBackup.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", enableToneTransfer.toString())
        }
        release {
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_RAW_BACKUP", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", "false")
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}
