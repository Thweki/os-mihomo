#!/bin/sh
# Runs only inside a disposable FreeBSD CI VM; does not install the package.
set -eu
export LC_ALL=C TZ=UTC
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -c safe.directory="$PWD" log -1 --format=%ct)}"
export SOURCE_DATE_EPOCH
version=$(sed -n 's/^VERSION?=[[:space:]]*//p' Makefile)
case "${BUILD_REF:-}" in
    refs/tags/v*)
        tagged=${BUILD_REF#refs/tags/v}
        [ "$tagged" = "$version" ] || { echo 'Tag and Makefile version must match' >&2; exit 1; }
        ;;
esac
# Pure fixture tests run in the target OS as well as the source-validation job.
php tests/test_patch.php
php tests/test_writes.php
php tests/test_api.php
VERSION="$version" make package
core_fixture=$(mktemp -d "$PWD/work/core-test.XXXXXX")
trap 'rm -rf "$core_fixture"' EXIT HUP INT TERM
cat > "$core_fixture/valid.yaml" <<'EOF'
allow-lan: false
mode: rule
log-level: silent
tun:
  enable: false
dns:
  enable: false
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF
# Syntax checks only: never start the core, listen on ports or apply network state.
core="$PWD/work/freebsd-pkg/stage/usr/local/bin/mihomo"
"$core" -t -d "$core_fixture" -f "$core_fixture/valid.yaml"
printf 'mixed-port: [invalid\n' > "$core_fixture/invalid.yaml"
if "$core" -t -d "$core_fixture" -f "$core_fixture/invalid.yaml"; then
    echo 'Core accepted invalid YAML' >&2; exit 1
fi
first_hash=$(sha256 -q dist/os-mihomo.pkg)
# Rebuild into an independent staging path. Source file mtimes are not inputs.
VERSION="$version" WORKDIR="$PWD/work/reproducibility" OUTPUT_NAME=os-mihomo-rebuilt.pkg make package
cmp dist/os-mihomo.pkg dist/os-mihomo-rebuilt.pkg
rm dist/os-mihomo-rebuilt.pkg
echo "Reproducible package verified: $first_hash"
export REPRODUCIBLE_PACKAGE_SHA256="$first_hash"
VERSION="$version" sh scripts/make_repo.sh
sh tests/test_repository.sh
# Inspect archive without executing package hooks.
pkg info -F dist/os-mihomo.pkg
pkg info -F dist/os-mihomo.pkg -l > dist/package-files.txt
for expected in Translator.php RuntimeStatus.php runtime_status.php network_status.volt os-mihomo.mo ui.js config.yaml.sample mihomo.sample; do
    grep -q "$expected" dist/package-files.txt || { echo "Missing package file: $expected" >&2; exit 1; }
done
if grep -Eq '/(config.yaml|sub/env|sub/template_config.yaml|rc.conf.d/mihomo)$' dist/package-files.txt; then
    echo 'Package must not own live configuration' >&2; exit 1
fi
python3 tools/reproducible_archive.py dist/repo dist/os-mihomo-repository.tar.gz
python3 tools/build_provenance.py
(cd dist
 sha256 -r os-mihomo.pkg os-mihomo-repository.tar.gz build-info.json package-files.txt > SHA256SUMS
 while read -r expected file; do
     sha256 -c "$expected" "$file" || exit 1
 done < SHA256SUMS
)
