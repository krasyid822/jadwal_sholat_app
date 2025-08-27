plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
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
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
    // Needed for AppCompatActivity used by native activities
    implementation("androidx.appcompat:appcompat:1.6.1")
    // WorkManager for periodic reliable background work
    implementation("androidx.work:work-runtime-ktx:2.8.1")
}

flutter {
    source = "../.."
}
