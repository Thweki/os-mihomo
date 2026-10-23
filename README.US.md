# os-mihomo

[![CI](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml/badge.svg)](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml)
[简体中文](README.md)

A Mihomo plugin with native OPNsense MVC pages, forms and tables. Components inherit the active OPNsense theme, and browser requests go through the plugin API.

## Features

- Overview with rates, totals, connections, proxy groups, latency tests and runtime mode.
- Traffic ranges of 1, 5 and 15 minutes, or 1 hour. Values use one decimal place. Samples are collected while the page is open; missing samples leave gaps.
- Native settings with per-field write controls and an advanced mode for controller, TUN and DNS options.
- A read-only YAML editor that requires explicit unlocking, change review, server-side backup and validation before saving.
- Configuration comparison across form, file and runtime values.
- Interface-based routing policies, previews and configuration history.
- Subscription updates and core/subscription logs with download and clear actions.
- English and Simplified Chinese, plus a gettext template. Charts use semantic colors from the current theme; there is no plugin theme switch.

Menu: `VPN → Proxy Suite`. Pages: `/ui/mihomo/*`. API: `/api/mihomo/*`. No embedded third-party dashboard or direct browser connection to the core controller is required.

## Requirements

The current build targets **OPNsense 26.7 / FreeBSD 15 amd64**. Plugin version: `1.1.0`; core version: `1.19.31-vincent`. Other versions require separate validation.

## Install

Download the `os-mihomo-freebsd15-amd64` artifact from a successful [Actions run](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml), or build it yourself. It contains the package, a package-repository archive, a file list and SHA-256 checksums.

```sh
while read -r expected file; do
    sha256 -c "$expected" "$file" || exit 1
done < SHA256SUMS
pkg add os-mihomo.pkg
```

Fresh installations disable autostart. Package hooks install files only: they do not configure interfaces, firewall, routes or DNS, or start the service. Defaults ship as `.sample` files and are copied only when the live file is absent.

Configure working nodes or a subscription before enabling network integration. Settings and policy Apply actions write the corresponding configuration; review their previews first. Subscription updates rebuild the configuration from the template and can replace manual edits.

Back up before migrating from another package with the same name, and inspect its uninstall hooks. Before removing this plugin, disable dependent network policies and stop the service yourself. User configuration is retained on removal.

## Build and validate

Build on FreeBSD 15 amd64 with `pkg`, `tar`, `xz`, `sha256`, and either `fetch` or `curl`:

```sh
make package   # dist/os-mihomo.pkg
make repo      # dist/repo/<ABI>/
```

The core version and checksum are pinned in [binary-source.json](packaging/freebsd/binary-source.json). Building does not install the package or run its hooks.

Source checks require Python 3, Node.js, PHP and a POSIX shell:

```sh
python3 tools/validate.py
```

See [CI/CD](docs/ci-cd.md) for automated checks, artifacts and tag-triggered draft releases.

## Translation

Edit `locales/<locale>.po` using `locales/os-mihomo.pot`, then regenerate and commit the plugin catalogs:

```sh
python3 tools/build_locales.py
python3 tools/build_locales.py --check
```

The plugin uses its own gettext domain without modifying system catalogs. Missing translations fall back to system translations or English.

## Credits

[Opnwall/OPNsense-repo](https://github.com/Opnwall/OPNsense-repo) supplies the original plugin assets and packaging basis. [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) provides the core, with FreeBSD builds from [Vincent-Loeng/clash-meta](https://github.com/Vincent-Loeng/clash-meta). Original copyright and license notices remain in the source files.
