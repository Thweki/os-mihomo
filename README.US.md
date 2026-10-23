<div align="center">
  <a href="README.md">中文</a> |
  <a href="README.US.md">English</a>
</div>

# os-mihomo

**Mihomo for OPNsense with a native OPNsense WebGUI**

![OPNsense](https://img.shields.io/badge/OPNsense-26.7-orange)
![FreeBSD](https://img.shields.io/badge/FreeBSD-15.1-999999)
![mihomo](https://img.shields.io/badge/mihomo-1.19.31--vincent-purple)
![plugin](https://img.shields.io/badge/plugin-os--mihomo-blue)
![i18n](https://img.shields.io/badge/i18n-zh__CN-green)

An **independently maintained OPNsense plugin project**: it installs
[mihomo](https://github.com/MetaCubeX/mihomo) (formerly Clash Meta) on OPNsense and manages it
from **OPNsense's own WebGUI**. No separate HTTP service, no embedded third-party dashboard.

The plugin is shipped as a **standard OPNsense plugin package**, so it can be installed,
upgraded and removed by the built-in **plugin manager** (`System → Firmware → Plugins`).

> The package name matches the upstream plugin (`os-mihomo`, the same plugin slot), which makes
> this a drop-in replacement/upgrade. The WebGUI, however, is a re-implementation: every page is
> native OPNsense MVC instead of the legacy `.php` pages.

---

## 1. Design principles

| Principle | How |
|---|---|
| **Native rendering** | Pages are rendered by OPNsense itself (Phalcon + Volt + Bootstrap 3 + opnsense theme). Routes `/ui/mihomo/*`, API `/api/mihomo/*` |
| **Browser never touches the controller** | mihomo's RESTful controller (`:9090`) binds to loopback only and is proxied by server-side PHP using the controller secret |
| **No third-party frontend** | No iframe, no zashboard/yacd/metacubexd, no external JS/CSS assets |
| **Auditable privileged actions** | Writing config, reading/clearing logs and running subscription updates all go through **configd** (root) instead of shell string building in PHP |
| **Validate before writing** | Raw YAML is checked with `mihomo -t` before it replaces the active file, the previous file is kept as a timestamped backup, and the patcher only touches the keys that actually change |
| **Service is off by default** | The plugin never enables autostart on its own; diagnostic APIs remain available without a persistent dashboard difference banner |

## 2. Features

Menu: `VPN → Proxy Suite → Mihomo / Settings / Subscription / Log File`

| Page | Route | Capabilities |
|---|---|---|
| **Mihomo** (overview) | `/ui/mihomo` | Service state and start/stop, boot-enable toggle, selectable traffic time ranges, cumulative traffic, memory/core version, proxy groups with node switch and latency test, runtime mode switch, active connections table (close one / close all) |
| **Settings** | `/ui/mihomo/settings` | Native form (service / controller / TUN / DNS / subscription) plus a raw YAML editor (validated with `mihomo -t`, timestamped backup, minimal one-line patching) and import from the active configuration file |
| **Subscription** | `/ui/mihomo/subscription` | Subscription URL and secret, one-click update (deliberately does **not** restart the service by default), live subscription log |
| **Log File** | `/ui/mihomo/log` | Core log / subscription log: line count, download, clear (read through configd, so no file permissions have to be loosened) |

API: `/api/mihomo/{service,settings,dashboard,subscription,log}/*`
Legacy URLs (`/mihomo.php`, `/mihomo_sub.php`, …) redirect (302) to the new pages.

## 3. Screenshots (real device, Chinese UI)

![Overview](docs/screenshots/09-overview-zh_CN.png)

![Settings](docs/screenshots/08-settings-zh_CN.png)

![Subscription](docs/screenshots/04-subscription.png)

![Log](docs/screenshots/05-log.png)

## 4. Install

Pick one of three paths:

| Path | Command / entry point | Touches system networking? | Use when |
|---|---|---|---|
| **A. Plugin manager** | `System → Firmware → Plugins → Install` (configure a plugin repository first, see §5) | No; file-only installation | Fresh devices; you want the firmware system to manage it |
| **B. Single package** | `pkg add -f os-mihomo.pkg` | Same as A | Offline distribution |
| **C. Safe deploy script** | `scripts/deploy.sh` (driven by `tools/remote.ps1`) | **No** — only writes the plugin's own files; never touches firewall, interfaces, DNS or routes | Devices already serving a production network (this is how this project was delivered) |

```sh
# Path C: file-by-file install, php -l / sh -n checks, menu cache clear, configd restart
powershell -File tools/deploy.ps1 -WithBinary   # first install (includes the core binary)
powershell -File tools/deploy.ps1               # later upgrades (keeps your config.yaml)
powershell -File tools/webtest.ps1              # end-to-end check: pages 200 / APIs 200 / unauthorized 302
```

Package hooks now install files only. They never configure interfaces, firewall, routes or DNS, or start/restart the service. Live settings are not package-owned: defaults ship as `.sample` files, are copied only when absent, and new installations have autostart disabled. Uninstall retains user configuration; stop dependent policies and the service yourself before removal.

Legacy upstream packages have network-changing hooks. Back up and inspect their uninstall hooks before migrating: this version cannot prevent an old package from running its own hooks.

Use `powershell -File tools/deploy.ps1 -UiOnly` for a UI-only update with backup and rollback. See [CI/CD](docs/ci-cd.md) for validation, FreeBSD artifacts and tag-triggered draft releases. The UI inherits the active OPNsense theme, uses one decimal place for traffic, and provides 1/5/15-minute and 1-hour views of samples collected while the page is open. English source strings, a Chinese catalog and a gettext template are included.

## 5. Publishing a plugin repository

The build chain produces a **standard OPNsense plugin repository tree** (ABI-scoped, same shape as
the official repos):

```sh
make package          # → dist/os-mihomo.pkg (native ABI by default)
make repo             # → dist/repo/<ABI>/
```

```text
dist/repo/FreeBSD:15:amd64/
├── os-mihomo-1.1.0.pkg        the plugin package
├── meta.conf / meta           repository metadata (pkg 2.x)
├── data.pkg / packagesite.pkg  catalog data
└── os-mihomo.conf             client-side repository config template
```

Upload that directory to any static host (or keep it in a local directory) and point a repository
config at it:

```sh
# /usr/local/etc/pkg/repos/os-mihomo.conf
os-mihomo: {
  url: "https://example.com/mihomo/FreeBSD:15:amd64",   # or file:///usr/local/opnsense/_bak/os-mihomo-repo/FreeBSD:15:amd64
  enabled: yes,
  priority: 20
}
```

```sh
pkg update        # refresh the catalog
```

**os-mihomo** then shows up under `System → Firmware → Plugins` and can be installed, upgraded and
removed there (the firmware system installs it with `pkg install -y os-mihomo` plus
`register.php install`).

<details>
<summary>Why this is "manageable by the plugin manager" — measured evidence</summary>

The Plugins page (`/ui/core/firmware`) consumes `configctl firmware remote` / `firmware local`,
where every line carries 9 `|||`-separated fields:
`name|||version|||comment|||flatsize|||locked|||automatic|||license|||repository|||origin`.
Any package whose `name` starts with `os-` and that resolves from a repository is listed as a plugin.
With this project's repository attached:

```text
os-mihomo|||1.1.0|||Mihomo proxy integration for OPNsense|||76.8MiB|||0|||0||||||os-mihomo|||opnsense/os-mihomo
os-mihomo|||1.0.4|||Mihomo proxy integration for OPNsense|||76.7MiB|||0|||0||||||opnwall|||opnsense/os-mihomo
        ^ this project (repository=os-mihomo)                     ^ upstream 1.0.4 (repository=opnwall)
```

`pkg version -t 1.1.0 1.0.4` → `>`, so the plugin manager treats it as an upgrade of the upstream package.
</details>

## 6. First run (read this first)

1. **Replace the nodes/subscription before starting the service.** Edit `Settings → Configuration File`,
   or submit a subscription on the `Subscription` page. The overview banner lists the current risks
   (placeholder nodes, TUN auto-route, strict route, DNS hijacking, controller exposed to the network).
2. **Decide about autostart**: `Settings → Service → Enable mihomo` (off by default; you choose).
3. After starting, the overview page shows proxy groups, node switching, connections and live rates.
4. Once stable, set `Settings → Log level` to `error` or `silent` to keep the log small.

> **About DNS**: if LAN clients use the OPNsense LAN address as their resolver, Unbound answers before
> the query ever reaches mihomo. To let mihomo handle DNS you can NAT-redirect LAN DNS, hand out an
> external resolver via DHCP, or forward Unbound to mihomo's listen port (`1053`). Upstream's
> The legacy upstream `+POST_INSTALL` did the last one and adds a `geosite:cn` filter to Fake-IP (domestic domains get
> real IPs, foreign ones get Fake-IPs). **This project never changes that for you** — DNS and TUN
> behaviour is controlled only by what you set explicitly in `Settings`.

## 7. Repository layout

The repository root **is** the plugin tree; `src/` mirrors the install paths:

```text
src/
├── etc/rc.conf.d/mihomo                                  boot enable switch
├── usr/bin/mihomo_sub                                    subscription CLI helper
└── usr/local/
    ├── bin/mihomo  +  etc/mihomo/{config.yaml,GeoIP.dat,GeoSite.dat,sub/}
    ├── etc/rc.d/mihomo                                   service script
    ├── etc/inc/plugins.inc.d/mihomo.inc                  registration with the OPNsense core
    ├── opnsense/version/mihomo                           plugin version metadata
    ├── opnsense/service/conf/actions.d/actions_mihomo.conf  14 configd actions
    ├── opnsense/scripts/mihomo/                          privileged scripts (config_apply/env/logtail/…)
    ├── opnsense/mvc/app/
    │   ├── models/OPNsense/Mihomo/       models, Config (Safety/Subscription/…), ACL, Menu
    │   ├── controllers/OPNsense/Mihomo/  page controllers + Api/* + forms/settings.xml
    │   └── views/OPNsense/Mihomo/        index/settings/subscription/log Volt templates
    └── www/mihomo*.php                                   legacy URLs → 302 redirects
```

## 8. Building

Build on FreeBSD / OPNsense (needs `pkg`, `tar`, `make`, `xz`, `sha256` and `curl` or `fetch`):

```sh
make package                  # native ABI (for plugin repositories)
make package ABI=universal    # portable ABI (single-file distribution only)
make repo                     # also produce the plugin repository tree dist/repo/<ABI>/
pkg info -F dist/os-mihomo.pkg
```

The core binary defaults to the in-tree asset `src/usr/local/bin/clash-meta-freebsd-amd64.xz` and is
only downloaded from [Vincent-Loeng/clash-meta](https://github.com/Vincent-Loeng/clash-meta) when
missing; its SHA256 from `packaging/freebsd/binary-source.json` is always verified.

## 9. Uninstall

```sh
# Plugin manager: System → Firmware → Plugins → Remove
# Or on the command line:
pkg delete os-mihomo
```

`+PRE_DEINSTALL` stops the service, removes the `tun_mihomo` interface and its firewall rule, reverts
the Unbound forwarding and cleans related cron entries; `+POST_DEINSTALL` clears the menu cache,
deletes `actions_mihomo.conf`, restarts configd and then removes `/usr/local/etc/mihomo`.
**Back up `/usr/local/etc/mihomo/` (configuration and subscription credentials) before uninstalling.**

## 10. Common commands

```sh
service mihomo start|stop|restart|status|rcvar   # service control
tail -f /var/log/mihomo.log                      # core log
sockstat -4 -l | egrep ':53|:7891|:9090'         # listening ports
ifconfig tun_mihomo                              # TUN interface
pfctl -sr | grep tun_mihomo                      # runtime rules
configctl mihomo status|config-current|env-get   # plugin configd actions
/usr/local/etc/rc.restart_webgui                 # restart the WebGUI (after view/i18n changes)
```

Scheduled subscription updates: `System → Settings → Cron`, add a task and pick the command
`Renew mihomo Subscription`.

## 11. Documentation

| Document | Content |
|---|---|
| [`docs/config-guide.md`](docs/config-guide.md) | **Configuration guide**: how the YAML file and the WebGUI options overlap, who wins, and how to check the configuration that is really in effect (with a three-way compare script) — currently Chinese |
| [`docs/report.md`](docs/report.md) | Delivery report: requirements, architecture, **real screenshots**, safety proof, verification matrix, rollback procedure, incident log |
| [`docs/design.md`](docs/design.md) | Design notes: MVC structure, API contract, configd actions, YAML patcher rules |
| [`AGENTS.md`](AGENTS.md) / [`TODO.md`](TODO.md) | Working manual / status board (safety red lines and verification method) |

## 12. Credits

[mihomo](https://github.com/MetaCubeX/mihomo) ·
[Vincent-Loeng/clash-meta](https://github.com/Vincent-Loeng/clash-meta) (FreeBSD core) ·
[Opnwall/OPNsense-repo](https://github.com/Opnwall/OPNsense-repo) (source of the runtime assets) ·
[OPNsense](https://opnsense.org/)

## 13. Disclaimer

> [!CAUTION]
> Unofficial plugin, not supported by the OPNsense team. The proxy core and the network settings it
> can touch have a wide blast radius: before enabling TUN / automatic route takeover / DNS hijacking
> on a device that serves a production network, make sure you understand the consequences.
> Use at your own risk.
