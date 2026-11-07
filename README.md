# AGP: manifest errors point at another checkout after a build-cache hit

`ProcessApplicationManifest` (`processReleaseMainManifest`) is a `@CacheableTask` whose main manifest input is `@PathSensitive(RELATIVE)`, so two copies of a project at different paths share its cache entry. But two of its outputs, the merge report (`build/outputs/logs/manifest-merger-release-report.txt`) and the blame file (`build/intermediates/manifest_merge_blame_file/…/manifest-merger-blame-release-report.txt`), name every source manifest by absolute path. After a cache hit, the second copy gets the first copy's paths. Lint and aapt2 map merged-manifest locations back to source through those files, so their errors in the second copy name the first copy's `AndroidManifest.xml`.

## Reproduction

Needs an Android SDK (`ANDROID_HOME`) with platform 36. The script copies this project into `work/first` and `work/second`, points both at one empty build cache with an init script, and builds each:

```sh
./reproduce.sh
```

Output with AGP 9.6.0-alpha03 and Gradle 9.9.0 (`<work>` is the script's `work` directory):

```
1. Lint: same project in two directories
== first (:app:lintRelease)
> Task :app:processReleaseMainManifest
<work>/first/app/src/main/AndroidManifest.xml:6: Error: The attribute android:dataExtractionRules only applies for Android 12 and higher; since minSdkVersion is API 26 you should also set android:fullBackupContent [DataExtractionRules]
== second (:app:lintRelease)
> Task :app:processReleaseMainManifest FROM-CACHE
<work>/first/app/src/main/AndroidManifest.xml:6: Error: The attribute android:dataExtractionRules only applies for Android 12 and higher; since minSdkVersion is API 26 you should also set android:fullBackupContent [DataExtractionRules]

2. aapt2: the second copy deletes a resource its unchanged manifest references
== second (:app:processReleaseResources)
> Task :app:processReleaseMainManifest UP-TO-DATE
     ERROR: <work>/first/app/src/main/AndroidManifest.xml:4:5-7:33: AAPT: error: resource xml/data_extraction_rules (aka com.example.repro:xml/data_extraction_rules) not found.

Absolute paths in the second copy's cached manifest-merge outputs:
<work>/second/app/build/outputs/logs/manifest-merger-release-report.txt:15 lines name <work>/first
<work>/second/app/build/intermediates/manifest_merge_blame_file/release/processReleaseMainManifest/manifest-merger-blame-release-report.txt:4 lines name <work>/first
```

## Expected

Errors in `work/second` name `work/second/app/src/main/AndroidManifest.xml`. Either the merge report and blame file are relocatable (paths relative to the project, or resolved against the consuming project when read), or the task doesn't reuse a cache entry whose outputs name another project directory.

## Actual

- `ProcessApplicationManifest` is `@CacheableTask`; `mainManifest` is `@InputFile @PathSensitive(RELATIVE)`.
- `reportFile` and `mergeBlameFile`, declared `@OutputFile @Optional` on `ManifestProcessor`, are written with absolute source paths (`ADDED from /abs/path/AndroidManifest.xml:…` and `-->/abs/path/AndroidManifest.xml:…`).
- Lint's variant model points `manifestMergeReport` at the report, and `LintClient.resolveMergeManifestSources` / `findManifestSourceLocation` map merged-manifest nodes back to source through it, so checks on the merged manifest (here `DataExtractionRules` from `ManifestDetector`) report the first copy's file. With the first copy deleted, lint falls back to the second copy's manifest but at the `<application>` element (line 4), not the attribute (line 6).
- `processReleaseResources` rewrites aapt2's errors through the blame file and prints the first copy's path, even after that copy is deleted.

The same happens with AGP 9.5.1. CI runners that check out at one fixed path don't see it. Builds at different paths that share a cache do: several clones or worktrees on one machine, CI agents with numbered workspaces, or developers who pull from a remote cache that CI fills.

## Environment

- AGP 9.6.0-alpha03 (also 9.5.1), lint 32.6.0-alpha03
- Gradle 9.9.0, JDK 25.0.2 (Temurin)
- macOS 27.2
