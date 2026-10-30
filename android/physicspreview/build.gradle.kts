// 貯金箱の物理を PC で動かして確かめる（アプリには入らない）
// アプリの CoinWorld.kt をそのまま写し、Box2D の窓口だけ PC 用（box2d パッケージ）に読み替えてテストする
plugins { alias(libs.plugins.kotlin.jvm) }

val generated = layout.buildDirectory.dir("generated/coinworld")
val copyCoinWorld by tasks.registering(Copy::class) {
    from(rootProject.file("app/src/main/java/jp/kakeibo/share/physics/CoinWorld.kt"))
    into(generated.map { it.dir("jp/kakeibo/share/physics") })
    filter { it.replace("import box2dandroid.*", "import box2d.*") }
}
kotlin.sourceSets["main"].kotlin.srcDir(generated)
tasks.named("compileKotlin") { dependsOn(copyCoinWorld) }

dependencies {
    implementation(libs.box2d.desktop)
    for (os in listOf("windows", "linux", "macos", "macos-arm64")) runtimeOnly(variantOf(libs.box2d.desktop) { classifier("natives-$os") })
    testImplementation(libs.junit)
}

tasks.test {
    systemProperty("kb.res", rootProject.file("app/src/main/res/drawable-nodpi").absolutePath)
    systemProperty("kb.out", layout.buildDirectory.dir("pile").get().asFile.absolutePath)
}
