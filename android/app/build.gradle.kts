import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Three compile gates exist. ENABLE_MATRIBOX_P01_RAW_BACKUP enables the read-only preset
// reader/backup and ENABLE_MATRIBOX_TONE_TRANSFER enables the productive preset transfer
// (P11..P99 only) together with the reader it depends on -- both remain debug-only and false in
// release; they are diagnostics/research features, not shipped product UI.
// REAL_MATRIBOX_WRITE (V5B.1) gates the separate, narrower NAM Clone-transfer send primitive
// (MatriboxNamCloneSendPort) -- independent of the other two, since it shares no code with
// presets/tone-transfer. Release hardening V1: this is now the hardware-confirmed, shipped
// product feature (NAM -> Clone 1/5), so release hardcodes it `true` -- a release build must be
// able to perform the transfer the product UI's own explicit confirmation flow just authorized.
// A debug build still defaults it `false` unless an explicit `--dart-define=REAL_MATRIBOX_WRITE=true`
// is passed, so a developer build never writes by accident. The historical probe/certification
// gates were removed with their tools; an old define is simply ignored and enables nothing.
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
// V5B.2b: same narrow dart-define mechanism as the other two gates -- false unless this EXACT
// build explicitly passes --dart-define=REAL_MATRIBOX_WRITE=true. Does not imply or enable
// anything else (no clone/model selection, no preset/Store path); those stay structurally
// impossible regardless of this flag (see MatriboxNamCloneTransferReference/Session).
val enableRealMatriboxWrite = requestedDefine("REAL_MATRIBOX_WRITE")

// Tone Match performance harness only: an explicit -PwyrmtoneBenchApplicationId may install the harness
// next to the real app. Anything that is not a ".bench" id of the product is rejected, so the property
// can never rename or replace the product package. Without the property the id is de.neevel.wyrmtone.
val benchApplicationId = project.findProperty("wyrmtoneBenchApplicationId") as String?
require(benchApplicationId == null || benchApplicationId.startsWith("de.neevel.wyrmtone.bench")) {
    "wyrmtoneBenchApplicationId must start with de.neevel.wyrmtone.bench (got $benchApplicationId)"
}

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
        // The product id stays unless a build explicitly passes -PwyrmtoneBenchApplicationId (or the
        // ORG_GRADLE_PROJECT_ environment variable): used only by the Tone Match Android performance
        // harness so it can be installed next to the real app without touching its data.
        applicationId = benchApplicationId ?: "de.neevel.wyrmtone"
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

        // Android NAM inference V1, section 17 (ABI discipline): a defaultConfig-level
        // `ndk.abiFilters` override was tried here and removed -- it did NOT actually
        // restrict which ABIs a plain `flutter build apk`/`assembleDebug` produces
        // (Flutter's own Gradle plugin adds its own default ABI set independently), and
        // it ACTIVELY CONFLICTS with Flutter's real, idiomatic restriction mechanism:
        // `flutter build apk --target-platform android-arm64 --split-per-abi` fails
        // with "Conflicting configuration: 'arm64-v8a' in ndk abiFilters cannot be
        // present when splits abi filters are set" as long as this override exists.
        // The correct way to build an arm64-v8a-only product APK is that Flutter CLI
        // flag combination, with no custom `ndk.abiFilters` here -- not a Gradle
        // config change. For this milestone, arm64-v8a present and tested (verified
        // in every debug build's lib/arm64-v8a/libwyrmtone_nam.so) is sufficient; the
        // armeabi-v7a/x86_64 copies a plain debug build also produces are unused by
        // the Samsung SM-F946B test device and harmless for local development.
        externalNativeBuild {
            cmake {
                // Build ONLY the shared library the Dart FFI bridge loads -- never the
                // desktop-only `nam_bridge_runner` console smoke-test executable.
                targets += "wyrmtone_nam"
                // AGP's CMake integration defaults to CMAKE_BUILD_TYPE=Debug (-O0) for a
                // debug app variant, same as the Windows dev DLL is never built that way
                // (native/nam_bridge/build.bat always passes -DCMAKE_BUILD_TYPE=Release).
                // An -O0 WaveNet inference over the 70s/3.36M-sample Reference Signal V4
                // is not just slower but impractically slow (observed: still running after
                // 4m42s per model, vs ~5-7s on the Release-built Windows DLL) -- this is a
                // DSP compute library, not something whose own debug symbols/stepping
                // matter, so it always builds Release regardless of the app's build type.
                arguments += "-DCMAKE_BUILD_TYPE=Release"
            }
        }
    }

    // Reuses native/nam_bridge/CMakeLists.txt byte-for-byte (see that file): the same
    // NeuralAmpModelerCore sources and the same wyrmtone_nam.h/.cpp C ABI the Windows
    // DLL build uses, cross-compiled for Android instead of duplicated.
    externalNativeBuild {
        cmake {
            path = file("../../native/nam_bridge/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        debug {
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_RAW_BACKUP", enableP01RawBackup.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", enableToneTransfer.toString())
            buildConfigField("boolean", "REAL_MATRIBOX_WRITE", enableRealMatriboxWrite.toString())
        }
        release {
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_RAW_BACKUP", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", "false")
            // Release hardening V1: the NAM Clone-transfer write path is the shipped product
            // feature, hardware-confirmed; the real safety boundary is the UI's own explicit
            // confirmation flow (see MatriboxNamCloneSendPort's doc comment), not this gate.
            buildConfigField("boolean", "REAL_MATRIBOX_WRITE", "true")
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
