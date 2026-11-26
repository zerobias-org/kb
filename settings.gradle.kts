// settings.gradle.kts — KB content monorepo
//
// Plugin resolution order: mavenLocal (for `publishToMavenLocal` dev builds
// of build-tools) → GitHub Packages Maven → gradle plugin portal → mavenCentral.
// Never via `includeBuild` of a sibling repo path: dev iteration goes through
// `./gradlew publishToMavenLocal` from build-tools so CI and local resolve
// the artifact the same way.

pluginManagement {
    repositories {
        mavenLocal()
        maven {
            url = uri("https://maven.pkg.github.com/zerobias-org/util")
            credentials {
                username = System.getenv("GITHUB_ACTOR")?.takeIf(String::isNotBlank) ?: "zerobias-org"
                // `?:` only falls through on null, not on an empty string. CI can export
                // READ_TOKEN set-but-empty, which would short-circuit the fallback and
                // auth with a blank password (401 → "plugin not found"). Skip blanks so a
                // later valid token (e.g. NPM_TOKEN) is used.
                password = listOf("READ_TOKEN", "NPM_TOKEN", "GITHUB_TOKEN")
                    .firstNotNullOfOrNull { System.getenv(it)?.takeIf(String::isNotBlank) } ?: ""
            }
        }
        gradlePluginPortal()
        mavenCentral()
    }
    plugins {
        id("zb.workspace") version "1.+"
        id("zb.base") version "1.+"
        id("zb.content") version "1.+"
    }
}

rootProject.name = "kb"

// Auto-discover all KB articles under package/.
// A directory is an article if it contains build.gradle.kts.
// The per-package build.gradle.kts is a one-line marker:
//   plugins { id("zb.content") }
// — same pattern as module/collectorbot. Matches zbb's design rule that
// every publishable subproject must have its own build.gradle.kts so
// `cd package/<article> && zbb gate` resolves to the right project.
// Project names mirror filesystem: package/kbc1-getting-started → :kbc1-getting-started
val packageDir = file("package")
if (packageDir.exists()) {
    packageDir.walkTopDown()
        .filter { it.name == "build.gradle.kts" }
        .forEach { buildFile ->
            val moduleDir = buildFile.parentFile
            val relativePath = moduleDir.relativeTo(packageDir).path
            val projectPath = relativePath.replace(File.separatorChar, ':')

            include(projectPath)
            project(":$projectPath").projectDir = moduleDir
        }
}
