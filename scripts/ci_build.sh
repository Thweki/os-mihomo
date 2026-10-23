#!/bin/sh
# Runs only inside a disposable FreeBSD CI VM; does not install the package.
set -eu
version=$(sed -n 's/^VERSION?=[[:space:]]*//p' Makefile)
case "${BUILD_REF:-}" in
    refs/tags/v*)
        tagged=${BUILD_REF#refs/tags/v}
        [ "$tagged" = "$version" ] || { echo 'Tag and Makefile version must match' >&2; exit 1; }
        ;;
esac
VERSION="$version" make package
VERSION="$version" sh scripts/make_repo.sh
# Inspect archive without executing package hooks.
pkg info -F dist/os-mihomo.pkg
pkg info -F dist/os-mihomo.pkg -l > dist/package-files.txt
for expected in Translator.php RuntimeStatus.php runtime_status.php network_status.volt os-mihomo.mo ui.js config.yaml.sample mihomo.sample; do
    grep -q "$expected" dist/package-files.txt || { echo "Missing package file: $expected" >&2; exit 1; }
done
if grep -Eq '/(config.yaml|sub/env|sub/template_config.yaml|rc.conf.d/mihomo)$' dist/package-files.txt; then
    echo 'Package must not own live configuration' >&2; exit 1
fi
tar -czf dist/os-mihomo-repository.tar.gz -C dist/repo .
(cd dist
 sha256 -r os-mihomo.pkg os-mihomo-repository.tar.gz > SHA256SUMS
 while read -r expected file; do
     sha256 -c "$expected" "$file" || exit 1
 done < SHA256SUMS
)
