import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

// Helper to read keystore config from environment variables or key.properties.
fun loadKeystoreConfig(): Map<String, String?> {
    val envStorePassword = System.getenv("KEYSTORE_PASSWORD")
    val envKeyPassword = System.getenv("KEY_PASSWORD")
    val envKeyAlias = System.getenv("KEY_ALIAS")
    val envKeyStorePath = System.getenv("KEYSTORE_PATH")

    val propsFile = rootProject.file("key.properties")
    val props = Properties()
    if (propsFile.exists()) {
        propsFile.inputStream().use { props.load(it) }
    }

    return mapOf(
        "storePassword" to (envStorePassword?.takeIf { it.isNotBlank() } ?: props.getProperty("storePassword")?.takeIf { it.isNotBlank() }),
        "keyPassword" to (envKeyPassword?.takeIf { it.isNotBlank() } ?: props.getProperty("keyPassword")?.takeIf { it.isNotBlank() }),
        "keyAlias" to (envKeyAlias?.takeIf { it.isNotBlank() } ?: props.getProperty("keyAlias")?.takeIf { it.isNotBlank() } ?: "upload"),
        "storeFile" to (envKeyStorePath?.takeIf { it.isNotBlank() } ?: props.getProperty("storeFile")?.takeIf { it.isNotBlank() } ?: "release.jks"),
    )
}

android {
    namespace = "com.neogamelab.neostation"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        // FORK REBRAND: applicationId differs from namespace so this fork
        // can install side-by-side with the upstream NeoStation APK on the
        // same device. The Kotlin namespace (com.neogamelab.neostation)
        // remains unchanged so existing `<provider android:name="...">` and
        // R class references stay valid without moving any source file.
        applicationId = "fr.idarius.idastation"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    buildTypes {
        release {
            val keystore = loadKeystoreConfig()
            val storeFilePath = keystore["storeFile"]!!
            val storePass = keystore["storePassword"]

            // Only sign with release keystore if credentials and file are present.
            // Otherwise fall back to debug signing (sideloading / no store).
            if (storePass != null && file(storeFilePath).exists()) {
                signingConfig = signingConfigs.create("release") {
                    storePassword = storePass
                    keyPassword = keystore["keyPassword"] ?: storePass
                    keyAlias = keystore["keyAlias"]!!
                    storeFile = file(storeFilePath)
                }
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro"
            )

            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:${project.property("kotlin_version")}")
}
