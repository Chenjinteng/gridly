allprojects {
    repositories {
        google()
        mavenCentral()
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

// 2026-10-17 D68.2 加:强制所有 plugin 子项目的 compileSdk ≥ 36
//   - 背景:file_picker 8.1.6 拉了 flutter_plugin_android_lifecycle 2.0.35,
//     其 AAR metadata 要求 "dependents must compile against 36+"
//   - gridly app 自己的 android/app/build.gradle.kts 已经 compileSdk=36,
//     但 :file_picker:checkReleaseAarMetadata / :file_picker:checkDebugAarMetadata
//     仍失败 —— 因为 file_picker 是 plugin 子项目,自己 android/build.gradle
//     锁 compileSdk 34,app 层的设置管不到子项目
//   - 修法:在 root android/build.gradle.kts 用 afterEvaluate 强制把所有
//     plugin 子项目的 compileSdk 提到 36
//   - 这是临时方案,等 file_picker 自己 release 把 compileSdk 升 36 后可移除
//   - AGP 9.x(Kotlin DSL)写法:用 BaseExtension 拿 android extension,
//     BaseExtension 在 com.android.application / com.android.library
//     两个 plugin 里都注册同名 extension,is check 兼容两者
//   - @Suppress("DEPRECATION") 忽略 AGP 9.0 的 deprecation 警告(BaseExtension
//     在 AGP 10.0 才移除,这个 fix 是临时的,跟 plugin 升级节奏对得上)
@Suppress("DEPRECATION")
import com.android.build.gradle.BaseExtension

subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is BaseExtension) {
            if (androidExt.compileSdkVersion < 36) {
                androidExt.compileSdkVersion(36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
