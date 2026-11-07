#!/bin/sh
# Builds two copies of this project at different paths with one shared, empty build cache,
# then prints the file each copy's errors point at.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work="$here/work"
rm -rf "$work"
mkdir -p "$work"

for copy in first second; do
    mkdir -p "$work/$copy"
    (cd "$here" && tar cf - --exclude ./work --exclude ./.gradle --exclude ./build --exclude ./app/build .) | (cd "$work/$copy" && tar xf -)
done

cat > "$work/cache.init.gradle" <<INIT
settingsEvaluated { settings ->
    settings.buildCache { local { directory = new File("$work/build-cache") } }
}
INIT

run() {
    (cd "$work/$1" && ./gradlew --init-script "$work/cache.init.gradle" --console=plain "$2" > "$work/$1-$3.log" 2>&1)
    echo "== $1 ($2)"
    grep -E 'Task :app:processReleaseMainManifest' "$work/$1-$3.log"
    grep -m1 -E 'Error:|ERROR:' "$work/$1-$3.log" | sed "s#$work#<work>#g"
}

echo "1. Lint: same project in two directories"
run first :app:lintRelease lint
run second :app:lintRelease lint

echo
echo "2. aapt2: the second copy deletes a resource its unchanged manifest references"
rm "$work/second/app/src/main/res/xml/data_extraction_rules.xml"
run second :app:processReleaseResources aapt

echo
echo "Absolute paths in the second copy's cached manifest-merge outputs:"
grep -c "$work/first/" \
    "$work/second/app/build/outputs/logs/manifest-merger-release-report.txt" \
    "$work/second/app/build/intermediates/manifest_merge_blame_file/release/processReleaseMainManifest/manifest-merger-blame-release-report.txt" |
    sed "s#$work#<work>#g; s#\$# lines name <work>/first#"
