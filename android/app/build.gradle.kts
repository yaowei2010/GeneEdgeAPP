plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val blueMagpiePocProperty = providers.gradleProperty("bluemagpiePoc").orNull
val blueMagpiePocRequested = when (blueMagpiePocProperty) {
    null, "false" -> false
    "true" -> true
    else -> throw GradleException(
        "bluemagpiePoc must be exactly 'true' or 'false'; got '$blueMagpiePocProperty'."
    )
}

android {
    namespace = "com.example.geneapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.geneapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 28)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    buildTypes {
        debug {
            buildConfigField(
                "boolean",
                "BLUEMAGPIE_POC_ENABLED",
                blueMagpiePocRequested.toString()
            )
            externalNativeBuild {
                cmake {
                    arguments += "-DGENEEDGE_BLUEMAGPIE_POC=${if (blueMagpiePocRequested) "ON" else "OFF"}"
                }
            }
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
        release {
            // This diagnostic runtime is never compiled into a release build.
            buildConfigField("boolean", "BLUEMAGPIE_POC_ENABLED", "false")
            externalNativeBuild {
                cmake {
                    arguments += "-DGENEEDGE_BLUEMAGPIE_POC=OFF"
                }
            }
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}
