allprojects {
    repositories {
        google()
        mavenCentral()
        // usb_serial'in yerel kütüphanesi (felHR85/UsbSerial) yalnız JitPack'te (USB fiş yazıcısı).
        maven("https://jitpack.io") {
            content { includeGroup("com.github.felHR85") }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
