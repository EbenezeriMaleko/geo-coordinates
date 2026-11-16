import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}
val googleMapsAndroidKey = providers.environmentVariable("GOOGLE_MAPS_ANDROID_API_KEY")
    .orElse(providers.gradleProperty("GOOGLE_MAPS_ANDROID_API_KEY"))
    .orElse(localProperties.getProperty("GOOGLE_MAPS_ANDROID_API_KEY", ""))

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.databenki.taref_gps"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.databenki.taref_gps"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsAndroidKey.get()

        // Enables multi-dex support for large apps
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            keyAlias     = keystoreProperties["keyAlias"]     as? String
            keyPassword  = keystoreProperties["keyPassword"]  as? String
            storeFile    = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as? String
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
	        isMinifyEnabled = true
	        isShrinkResources = true
	        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}


dependencies {
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("com.google.android.play:app-update-ktx:2.1.0")
    implementation("androidx.concurrent:concurrent-futures:1.1.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
