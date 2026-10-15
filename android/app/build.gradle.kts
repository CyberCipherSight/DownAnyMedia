import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun releaseProperty(name: String): String? =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }

android {
    namespace = "com.example.down_any_media"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.downanymedia.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobApplicationId"] =
            releaseProperty("admobApplicationId")
                ?: "ca-app-pub-3940256099942544~3347511713"
        // Flutter selects supported ABIs. Do not force every ABI here: it
        // conflicts with --split-per-abi and duplicates large media runtimes.
    }

    signingConfigs {
        create("release") {
            releaseProperty("storeFile")?.let {
                storeFile = rootProject.file(it)
            }
            storePassword = releaseProperty("storePassword")
            keyAlias = releaseProperty("keyAlias")
            keyPassword = releaseProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            keepDebugSymbols += listOf("**/libpython.zip.so", "**/libffmpeg.zip.so")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    val youtubedlAndroid = "0.18.1"

    implementation("io.github.junkfood02.youtubedl-android:library:$youtubedlAndroid")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:$youtubedlAndroid")
}
