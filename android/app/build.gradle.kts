plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.tidal_connect_lite"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.tidal_connect_lite"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    testOptions {
        // JVM 단위 테스트에서 android.util.Log 같은 Android 메서드가 예외 대신 기본값을 돌려주게 한다.
        // 프록시 서버가 요청마다 로그를 남기므로 이 설정이 없으면 테스트할 수 없다.
        unitTests.isReturnDefaultValues = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.tidal.sdk:auth:0.10.1")
    implementation("com.tidal.sdk:player:0.0.70")
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    // 속성 기반 테스트. 프로젝트의 Kotlin(2.1.0)보다 새 표준 라이브러리를 요구하므로 버전을 정확히 고정한다.
    testImplementation("io.kotest:kotest-property:6.2.7")
    // 프록시 테스트에서 TIDAL CDN을 대신하는 로컬 서버. 앱의 OkHttp와 같은 버전을 쓴다.
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}
