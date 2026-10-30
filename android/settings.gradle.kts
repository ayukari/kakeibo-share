pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "KakeiboShare"
include(":app")
include(":physicspreview")   // 貯金箱の物理を PC で動かして確かめる（アプリには入らない）
