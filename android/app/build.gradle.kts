plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

<<<<<<< HEAD
// Environment variables helper
fun getEnvOrDefault(name: String, defaultValue: String): String {
    return System.getenv(name) ?: defaultValue
}

fun getEnvOrDefault(name: String, defaultValue: Int): Int {
    return System.getenv(name)?.toIntOrNull() ?: defaultValue
}

android {
    namespace = "jadwalsholat.rasyid"
    
    // Compile SDK dari environment atau default
    compileSdk = getEnvOrDefault("ANDROID_COMPILE_SDK", 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
=======
android {
    namespace = "com.example.jadwal_sholat_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
>>>>>>> ea2dca7892bbabe0ff12dcf370e13c093c8f69d2
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
<<<<<<< HEAD
        jvmTarget = "21"
    }

    defaultConfig {
        applicationId = getEnvOrDefault("APP_PACKAGE_NAME", "jadwalsholat.rasyid")
        
        // SDK versions dari environment variables
        minSdk = getEnvOrDefault("ANDROID_MIN_SDK", 24)
        targetSdk = getEnvOrDefault("ANDROID_TARGET_SDK", 36)
        
        // Version dari environment variables
        versionCode = getEnvOrDefault("BUILD_NUMBER", flutter.versionCode ?: 1)
        versionName = getEnvOrDefault("APP_VERSION", flutter.versionName ?: "1.0.0")
        
        // App name dari environment
        resValue("string", "app_name", getEnvOrDefault("APP_NAME", "Jadwal Sholat App"))
        
        // Enable multidex for better performance
        multiDexEnabled = true
    }

    // Lint configuration untuk release builds
    lint {
        disable += listOf(
            "Instantiatable", // Disable instantiatable check untuk third-party libs
            "MissingTranslation",
            "ExtraTranslation"
        )
        abortOnError = false
        warningsAsErrors = false
        baseline = file("lint-baseline.xml")
    }

    buildTypes {
        debug {
            isDebuggable = true
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        
        release {
            isMinifyEnabled = getEnvOrDefault("ENABLE_MINIFY", "false").toBoolean()
            isShrinkResources = getEnvOrDefault("ENABLE_SHRINK_RESOURCES", "false").toBoolean()
            
            // Signing configuration dari environment variables
            val keystorePath = System.getenv("KEYSTORE_PATH")
            val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
            val keyAliasEnv = System.getenv("KEY_ALIAS")
            val keyPasswordEnv = System.getenv("KEY_PASSWORD")
            
            if (keystorePath != null && keystorePassword != null && keyAliasEnv != null && keyPasswordEnv != null) {
                signingConfig = signingConfigs.create("release") {
                    storeFile = file(keystorePath)
                    storePassword = keystorePassword
                    keyAlias = keyAliasEnv
                    keyPassword = keyPasswordEnv
                }
            } else {
                // Fallback to debug signing for development
                signingConfig = signingConfigs.getByName("debug")
            }
=======
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.jadwal_sholat_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
>>>>>>> ea2dca7892bbabe0ff12dcf370e13c093c8f69d2
        }
    }
}

dependencies {
<<<<<<< HEAD
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
    // Needed for AppCompatActivity used by native activities
    implementation("androidx.appcompat:appcompat:1.6.1")
    // WorkManager for periodic reliable background work
    implementation("androidx.work:work-runtime-ktx:2.8.1")
=======
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
>>>>>>> ea2dca7892bbabe0ff12dcf370e13c093c8f69d2
}

flutter {
    source = "../.."
}
<<<<<<< HEAD
=======

tasks.whenTaskAdded {
    if (name == "testDebugUnitTest") {
        enabled = false
    }
}
>>>>>>> ea2dca7892bbabe0ff12dcf370e13c093c8f69d2
