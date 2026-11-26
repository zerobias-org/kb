import com.zerobias.buildtools.content.SchemaPrimitives

plugins {
    id("zb.workspace")
}

group = "com.zerobias.content"

// ════════════════════════════════════════════════════════════
// KB content validator — owned by this repo.
//
// Philosophy (per Chris/Kevin): the dataloader is the source of truth
// for schema rules (KbArticleType enum, application lookup, keywords
// shape, relatesTo resolution, previewImageUrl parse, etc.). Re-validating
// those here just creates drift risk — when the dataloader tightens a
// rule, the gate gets stale.
//
// This validator only enforces things the dataloader CANNOT or DOES NOT
// check:
//
//   1. Filesystem ↔ npm ↔ zerobias-block triangulation. Dataloader
//      reads zerobias.package but never the npm `name` field, and has
//      no view of the on-disk directory layout. A wrong npm name
//      publishes under the wrong package and only surfaces in prod.
//
//   2. _index.md frontmatter `code` ↔ directory agreement. The KB
//      dataloader reads `code` from the `_index.md` frontmatter, while
//      npm name / zerobias.package derive from the directory name. If
//      the frontmatter code drifts from the directory, the artifact
//      loads under one identity and publishes under another.
//
//   3. Repo-wide unique `code`s (separate :validateUniqueCodes task
//      registered below). KB has no `id` UUID in its frontmatter — the
//      stable identifier is `code` (kbc1, kbc2, …). Dataloader sees one
//      artifact at a time; a duplicate code only surfaces in prod when
//      the second article tries to overwrite the first DB row.
//
// Everything else (KbArticleType validity, application existence,
// keywords/relatesTo shape, ReleaseNotes extendedProperties, URL parse,
// etc.) is delegated to the dataloader running in
// testIntegrationDataloader during gate.
// ════════════════════════════════════════════════════════════
extra["contentValidator"] = { proj: org.gradle.api.Project ->
    val projectDir = proj.projectDir
    val tag = "[kb-validator] ${proj.path}"

    require(projectDir.resolve("_index.md").isFile)    { "$tag _index.md missing in ${projectDir.path}" }
    require(projectDir.resolve("package.json").isFile) { "$tag package.json missing in ${projectDir.path}" }
    require(projectDir.resolve(".npmrc").isFile)       { "$tag .npmrc missing in ${projectDir.path}" }

    // ── 1. Filesystem ↔ npm ↔ zerobias-block triangulation ──
    // KB layout is package/<dir>/ where dir = "kbc<number>-<slug>".
    //   code            = dir up to the first '-'   (e.g. kbc9)
    //   npm name        = @zerobias-org/kb-<dir>
    // The prefix is "kbc" (kb, community), NOT bare "kb": auditlogic/kb owns
    // kb<number>. It starts with "kb" on purpose — the UI, the theme and the link
    // unfurl all recognise an article code by /^(kb|ct)/, so kbc<number> works
    // everywhere without changing them.
    // Both repos load into the same catalog and render into the same CDN
    // directory, so a shared prefix would let one repo overwrite the other.
    //   zerobias.package = zerobias.<code>.kb
    // Confirmed against the dataloader's KBFileHandler/Validator
    // (Validator.ts reads packageContents.zerobias ?? .auditmation).
    val dir = projectDir.name
    val code = dir.substringBefore("-")
    require(code.matches(Regex("^kbc[0-9]+$"))) {
        "$tag directory '$dir' must be named 'kbc<number>-<slug>' (derived code='$code' is not kbc<number>; kb<number> belongs to auditlogic/kb)"
    }

    // ── 2. _index.md frontmatter `code` ↔ directory agreement ──
    val frontmatterCode = readFrontmatterValue(projectDir.resolve("_index.md"), "code")
    require(frontmatterCode == code) {
        "$tag _index.md frontmatter code='$frontmatterCode' must equal directory-derived code '$code'"
    }

    val pkgDoc = SchemaPrimitives.parseJson(projectDir.resolve("package.json"))
    SchemaPrimitives.requirePackageIdentity(
        pkgDoc,
        expectedNpmName = "@zerobias-org/kb-$dir",
        expectedZerobiasPackage = "zerobias.$code.kb",
        field = "$tag package.json",
    )

    proj.logger.lifecycle("$tag: code=$code")
}

/**
 * Extract a scalar value from the YAML frontmatter block of a Hugo
 * `_index.md` (the lines between the first two `---` fences).
 *
 * We can't hand `_index.md` to SchemaPrimitives.parseYaml: snakeyaml's
 * single-document loader throws on the trailing markdown body (it sees a
 * second `---` document boundary). The frontmatter is small and flat for
 * the fields we triangulate on, so a direct line scan is robust and
 * avoids pulling the markdown body into a YAML parse.
 */
fun readFrontmatterValue(indexMd: java.io.File, key: String): String? {
    val lines = indexMd.readLines()
    val start = lines.indexOfFirst { it.trim() == "---" }
    if (start < 0) return null
    val end = lines.drop(start + 1).indexOfFirst { it.trim() == "---" }
    if (end < 0) return null
    val frontmatter = lines.subList(start + 1, start + 1 + end)
    val prefix = "$key:"
    val line = frontmatter.firstOrNull { it.trimStart().startsWith(prefix) } ?: return null
    return line.trimStart().removePrefix(prefix).trim().trim('"', '\'').ifBlank { null }
}

// ════════════════════════════════════════════════════════════
// :validateUniqueCodes — repo-wide cross-cut.
//
// Walks every kb package directory and fails if two articles resolve to
// the same `code` (e.g. both `kbc9-foo` and `kbc9-bar` → kbc9). KB has no
// `id` UUID, so `code` is the stable identifier. The dataloader processes
// one artifact at a time and never sees the collision; it only surfaces
// in prod when the second article tries to overwrite the first DB row.
// Wired as a dependency of every per-package validateContent so any gate
// run picks it up.
// ════════════════════════════════════════════════════════════
val validateUniqueCodes by tasks.registering {
    group = "verification"
    description = "Fail if two KB articles resolve to the same code"

    val packageDir = layout.projectDirectory.dir("package").asFile
    inputs.files(
        fileTree(packageDir) {
            include("**/package.json")
            exclude("**/node_modules/**")
        }
    )

    doLast {
        val byCode = mutableMapOf<String, MutableList<String>>()
        packageDir.listFiles()
            ?.filter { it.isDirectory && it.name.matches(Regex("^kbc[0-9]+-.*")) }
            ?.forEach { d ->
                val code = d.name.substringBefore("-")
                byCode.getOrPut(code) { mutableListOf() }.add(d.relativeTo(rootDir).path)
            }

        val collisions = byCode.filterValues { it.size > 1 }
        if (collisions.isNotEmpty()) {
            val report = collisions.entries.joinToString("\n") { (code, paths) ->
                "  $code\n    " + paths.joinToString("\n    ")
            }
            throw GradleException("[validateUniqueCodes] duplicate codes across the repo:\n$report")
        }
        logger.lifecycle("[validateUniqueCodes] ${byCode.size} unique codes across ${byCode.values.sumOf { it.size }} articles")
    }
}

// Make every per-package validateContent depend on the repo-wide unique-code
// check. Gradle deduplicates, so running gate on N packages still fires
// :validateUniqueCodes exactly once.
subprojects {
    tasks.matching { it.name == "validateContent" }.configureEach {
        dependsOn(rootProject.tasks.named("validateUniqueCodes"))
    }
}

val projectPaths by tasks.registering {
    group = "info"
    description = "Output project-to-directory mappings for tooling (used by zbb CLI)"
    doLast {
        subprojects.filter { it.buildFile.exists() }.forEach { p ->
            println("${p.path}=${p.projectDir.relativeTo(rootDir)}")
        }
    }
}

val changedModules by tasks.registering {
    group = "info"
    description = "List KB articles changed since last version tag"
    doLast {
        val lastTag = try {
            providers.exec {
                commandLine("git", "describe", "--tags", "--abbrev=0")
            }.standardOutput.asText.get().trim()
        } catch (e: Exception) {
            logger.warn("No version tags found -- listing all articles as changed")
            null
        }

        val diffArgs = if (lastTag != null) {
            listOf("git", "diff", "--name-only", lastTag, "HEAD")
        } else {
            listOf("git", "ls-files")
        }

        val result = providers.exec {
            commandLine(diffArgs)
        }.standardOutput.asText.get()

        // KB is depth 1: package/<dir>/... → take the single segment after package/.
        val changed = result.lines()
            .filter { it.startsWith("package/") }
            .map { it.split("/").drop(1).take(1).joinToString("/") }
            .distinct()
            .filter { it.isNotEmpty() }

        changed.forEach { println(it) }
    }
}
