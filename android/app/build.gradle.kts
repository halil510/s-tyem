import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ─────────────────────────────────────────────────────────────────────
// İMZA ANAHTARI — telefondaki uygulamanın "Güncelle" ile verisi korunarak
// güncellenebilmesi için HER APK AYNI anahtarla imzalanmalı (hangi
// bilgisayarda derlenirse derlensin).
//
// Anahtar GİT'E GİRMEZ (depo herkese açık). Aranan yerler, sırasıyla:
//   1) android/key.properties
//   2) <kullanıcı klasörü>/.sutyem/key.properties   (ör. C:\Users\aes\.sutyem)
// key.properties içindeki storeFile göreli ise, key.properties'in
// bulunduğu klasöre göre çözülür.
//
// Anahtar bulunamazsa derleme DURUR: başka anahtarla imzalanmış bir APK
// telefonda "Uygulama yüklenmedi" verir ve tek çare uygulamayı silmektir
// (= tüm veriler silinir). Bkz. SUTYEM.md "İmza anahtarı".
// ─────────────────────────────────────────────────────────────────────
val anahtarDosyasi: File? = listOf(
    rootProject.file("key.properties"),
    File(System.getProperty("user.home"), ".sutyem/key.properties"),
).firstOrNull { it.exists() }

val anahtar = Properties().apply {
    anahtarDosyasi?.inputStream()?.use { load(it) }
}

android {
    namespace = "com.example.sut_yem_clean"
    compileSdk = 36        // <<< ZORUNLU GÜNCELLEME

    ndkVersion = flutter.ndkVersion

    defaultConfig {
        // KALICI paket adı. DEĞİŞTİRME: değişirse telefon bunu ayrı (boş) bir
        // uygulama sayar, veriler yeni uygulamaya geçmez.
        applicationId = "com.sutyem.pro"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    signingConfigs {
        if (anahtarDosyasi != null) {
            create("sutyem") {
                keyAlias = anahtar.getProperty("keyAlias")
                keyPassword = anahtar.getProperty("keyPassword")
                storePassword = anahtar.getProperty("storePassword")
                val yol = File(anahtar.getProperty("storeFile"))
                storeFile = if (yol.isAbsolute) yol else File(anahtarDosyasi.parentFile, yol.path)
            }
        }
    }

    buildTypes {
        // Debug da release de AYNI anahtarla: hangisi yüklenirse yüklensin
        // diğerinin üstüne "Güncelle" olarak kurulur, veri kaybolmaz.
        getByName("release") {
            if (anahtarDosyasi != null) signingConfig = signingConfigs.getByName("sutyem")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("debug") {
            if (anahtarDosyasi != null) signingConfig = signingConfigs.getByName("sutyem")
        }
    }

    packaging {
        resources.excludes += setOf(
            "META-INF/LICENSE",
            "META-INF/LICENSE.txt",
            "META-INF/NOTICE",
            "META-INF/NOTICE.txt"
        )
    }
}

// Anahtar yoksa APK üretme (yanlış anahtarla imzalı APK = veri kaybı riski).
gradle.taskGraph.whenReady {
    val apkUretiliyor = allTasks.any { it.name.startsWith("package") || it.name.startsWith("assemble") || it.name.startsWith("bundle") }
    if (apkUretiliyor && anahtarDosyasi == null) {
        throw GradleException(
            "\n\nİMZA ANAHTARI BULUNAMADI — APK üretilmedi.\n" +
            "'.sutyem' klasörünü (sutyem-release.jks + key.properties) yedeğinden\n" +
            "  ${System.getProperty("user.home")}${File.separator}.sutyem\n" +
            "konumuna kopyalayın. Ayrıntı: SUTYEM.md → 'İmza anahtarı'.\n"
        )
    }
}

flutter {
    source = "../.."
}

// Release derlemesinden sonra sürüm numaralı kopya: Sutyem-1.2.6+15.apk
// (flutter-apk klasöründe, app-release.apk'nın yanında). Orijinal ad KALIR:
// Flutter aracı APK'yı o adla arar. Kaynak, Gradle'ın kendi çıktısı (apk/release).
tasks.whenTaskAdded {
    if (name == "assembleRelease") {
        doLast {
            val cikti = layout.buildDirectory.get().asFile
            val kaynak = File(cikti, "outputs/apk/release/app-release.apk")
            val hedefKlasor = File(cikti, "outputs/flutter-apk")
            if (kaynak.exists()) {
                hedefKlasor.mkdirs()
                val ad = "Sutyem-${flutter.versionName}+${flutter.versionCode}.apk"
                kaynak.copyTo(File(hedefKlasor, ad), overwrite = true)
                println("Sürüm adlı kopya: ${File(hedefKlasor, ad)}")
            }
        }
    }
}
