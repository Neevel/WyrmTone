import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Fail closed. The six independent experimental probes/readers below are
// mutually exclusive with each other and with the P01 raw-backup/gain-write
// pair in every build. ENABLE_MATRIBOX_P01_GAIN_WRITE additionally enables
// the raw-backup read/backup capability it depends on -- the Safe Write
// Lab's prepare step reads and backs up P01 before it can plan or send a
// write, so a gain-write build has BOTH ENABLE_MATRIBOX_P01_RAW_BACKUP and
// ENABLE_MATRIBOX_P01_GAIN_WRITE true, while still excluding every
// unrelated experimental probe. ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION likewise enables
// raw backup, is exclusive with GAIN_WRITE and every experimental probe;
// ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION likewise, and is exclusive with the
// AMP certification too. Requesting only ENABLE_MATRIBOX_P01_RAW_BACKUP
// still enables the read/backup path alone, with the write path left off.
val decodedDartDefines = providers.gradleProperty("dart-defines").orNull?.split(",")
    ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull() }
    .orEmpty()
fun requestedDefine(name: String): Boolean =
    decodedDartDefines.count { it.startsWith("$name=") } == 1 &&
        decodedDartDefines.single { it.startsWith("$name=") } == "$name=true"
val requestedGain41Probe = requestedDefine("ENABLE_MATRIBOX_WRITE_PROBE")
val requestedPresetP01Probe = requestedDefine("ENABLE_MATRIBOX_PRESET_P01_PROBE")
val requestedP01ReadProbe = requestedDefine("ENABLE_MATRIBOX_P01_READ_PROBE")
val requestedP01FullReadProbe = requestedDefine("ENABLE_MATRIBOX_P01_FULL_READ_PROBE")
val requestedP01FullReadProbeV3A = requestedDefine("ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A")
val requestedP01RawBackup = requestedDefine("ENABLE_MATRIBOX_P01_RAW_BACKUP")
val requestedP01GainWrite = requestedDefine("ENABLE_MATRIBOX_P01_GAIN_WRITE")
val requestedSol100OdCertification = requestedDefine("ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION")
val requestedFullLive = requestedDefine("ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION")
val requestedAngelsProduct = requestedDefine("ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION")
val requestedToneTransfer = requestedDefine("ENABLE_MATRIBOX_TONE_TRANSFER")
val requestedFamilyExpansion = requestedDefine("ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1")
val enableWriteProbe = requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedP01RawBackup && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedFullLive && !requestedAngelsProduct && !requestedToneTransfer && !requestedFamilyExpansion
val enablePresetP01Probe = requestedPresetP01Probe && !requestedGain41Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedP01RawBackup && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedFullLive && !requestedAngelsProduct && !requestedToneTransfer && !requestedFamilyExpansion
val enableP01ReadProbe = requestedP01ReadProbe && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedP01RawBackup && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedFullLive && !requestedAngelsProduct && !requestedToneTransfer && !requestedFamilyExpansion
val enableP01FullReadProbe = requestedP01FullReadProbe && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbeV3A && !requestedP01RawBackup && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedFullLive && !requestedAngelsProduct && !requestedToneTransfer && !requestedFamilyExpansion
val enableP01FullReadProbeV3A = requestedP01FullReadProbeV3A && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01RawBackup && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedFullLive && !requestedAngelsProduct && !requestedToneTransfer && !requestedFamilyExpansion
val enableP01RawBackup = (requestedP01RawBackup || requestedP01GainWrite || requestedSol100OdCertification || requestedFullLive || requestedAngelsProduct || requestedToneTransfer || requestedFamilyExpansion) && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A
val enableP01GainWrite = requestedP01GainWrite && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedSol100OdCertification && !requestedFullLive && !requestedAngelsProduct && !requestedToneTransfer && !requestedFamilyExpansion

val enableSol100OdCertification = requestedSol100OdCertification && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedP01GainWrite && !requestedFullLive && !requestedAngelsProduct && !requestedToneTransfer && !requestedFamilyExpansion

val enableFullLive = requestedFullLive && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedAngelsProduct && !requestedToneTransfer && !requestedFamilyExpansion
val enableAngelsProduct = requestedAngelsProduct && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedFullLive && !requestedToneTransfer && !requestedFamilyExpansion
val enableToneTransfer = requestedToneTransfer && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedFullLive && !requestedAngelsProduct && !requestedFamilyExpansion
val enableFamilyExpansion = requestedFamilyExpansion && !requestedGain41Probe && !requestedPresetP01Probe && !requestedP01ReadProbe && !requestedP01FullReadProbe && !requestedP01FullReadProbeV3A && !requestedP01GainWrite && !requestedSol100OdCertification && !requestedFullLive && !requestedAngelsProduct && !requestedToneTransfer

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
            buildConfigField("boolean", "ENABLE_MATRIBOX_WRITE_PROBE", enableWriteProbe.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_PRESET_P01_PROBE", enablePresetP01Probe.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_READ_PROBE", enableP01ReadProbe.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_FULL_READ_PROBE", enableP01FullReadProbe.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A", enableP01FullReadProbeV3A.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_RAW_BACKUP", enableP01RawBackup.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_GAIN_WRITE", enableP01GainWrite.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION", enableSol100OdCertification.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION", enableFullLive.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION", enableAngelsProduct.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", enableToneTransfer.toString())
            buildConfigField("boolean", "ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1", enableFamilyExpansion.toString())
        }
        release {
            buildConfigField("boolean", "ENABLE_MATRIBOX_WRITE_PROBE", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_PRESET_P01_PROBE", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_READ_PROBE", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_FULL_READ_PROBE", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_RAW_BACKUP", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_P01_GAIN_WRITE", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", "false")
            buildConfigField("boolean", "ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1", "false")
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
