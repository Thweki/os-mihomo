# os-mihomo

**Native Mihomo management for OPNsense.**

[![CI](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml/badge.svg)](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml)
[简体中文](README.md)

os-mihomo brings traffic monitoring, proxy groups, configuration, subscriptions and routing policies into the OPNsense WebGUI. It uses native OPNsense MVC pages, forms and tables, inherits the active system theme, and includes English and Simplified Chinese interfaces.

Browser requests go through the OPNsense plugin API. The server connects to the Mihomo controller over loopback with its authentication secret. No controller port needs to be exposed to the browser, and no embedded third-party dashboard or separate web server is required.

## Features

Open **VPN → Proxy Suite** after installation.

| Page | Capabilities |
| --- | --- |
| Mihomo overview | Live rates, traffic totals, active connections, loaded routing rule count, process memory, current forwarding, proxy groups, latency tests, runtime mode and service status |
| Settings | Native forms, write locks, change previews and discard, reapply, advanced options, YAML editing and validation, configuration comparison and DNS status |
| Policy Routing | Current forwarding and rule details; interface policies, change previews, network bindings, configuration history and restore |
| Subscription | Submit updates; view task state, last success, exit code and execution logs |
| Log File | Filter loaded lines by text and severity, toggle line wrapping, hide timestamps, pause refresh, switch sources and line counts, download or clear logs |

On the log page, **Download filtered log** saves exactly the already-visible, redacted lines as a UTF-8 `.log` file without another request. It reflects the current text, severity, surrounding-line and timestamp-display choices. The button is disabled without visible text. The separate **Download log** action still fetches up to 5,000 lines, independently of the display options.

In **Log File**, enter literal text in **Filter log**, then select **Surrounding lines → 2 before and after** or **5 before and after** to read nearby events. Search ignores case and only uses the selected number of loaded lines. Overlapping windows are merged in log order; the counts distinguish matching lines from all shown lines. **Matches only** restores the narrow filter, and clearing the search shows the loaded lines at the selected severity. Context works while refresh is paused and is recomputed when new logs arrive. The severity selection still limits what can be displayed.

In **Log File**, choose **Log severity** to show one exact level (Debug, Info, Warning, Error, Fatal or Panic), combined with the text filter. **All levels** is the default on each page visit. The filter recognizes Mihomo's `time=… level=…` file headers and logrus console headers, including colored output; words inside messages do not determine severity. **Unknown level** shows unrecognized lines, including unstructured subscription output and continuation lines. Choices survive refreshes and source/line-count changes during the visit. Only loaded lines are filtered, counts show visible/loaded lines, and downloads still include all levels. This does not change the core's logging configuration.

In **Log File**, clear **Wrap lines** to keep each log entry on one line and scroll horizontally; enable it to fit long lines to the panel, including long URLs. Wrapping starts enabled on each page visit. The choice survives filtering, refreshes and source changes during that visit. It only changes the display: line counts, selected text and downloads retain the original logical lines. If you are at the bottom, toggling keeps the newest entries in view.

In **Log File**, select **Hide timestamps** to make messages easier to scan; clear it to restore timestamps instantly, even with auto refresh paused. This hides recognized leading core (`time="…"`) and subscription (`[YYYY-MM-DD HH:MM:SS]`) timestamps only. Unknown formats and dates inside messages stay visible. Filtering still searches the full original lines, and downloads retain timestamps. The choice lasts for this page visit across refreshes and source changes; reloading shows timestamps again.

**Loaded routing rules** in the overview summary counts top-level entries returned by the running Mihomo controller, including rule-provider references counted once each; it does not expand provider contents or count PF firewall rules. The count refreshes every 30 seconds while the page is visible. An empty list shows **0**; failed or malformed reads show **Unavailable**. The count describes loaded rules even in Global or Direct mode, not rule matches or traffic activity.

Traffic charts cover the last **1 minute, 5 minutes, 15 minutes or 1 hour**, with values shown to one decimal place. Samples are collected while the overview is open, and missing samples leave gaps. There is no background long-term traffic storage. Charts follow the active OPNsense theme without a separate theme switch.

Use **Filter proxy names** to narrow the visible proxy rows by a literal case-insensitive name substring. Clear the filter to restore the complete list. Group latency tests still test every node in the selected group; filtering does not change routing or send requests.

In **Active Connections**, **Visible connections** counts the rows on the current table page after each search, page change or refresh. Empty results show zero; loading shows `—` and an unavailable controller shows **Unavailable**. This count describes the table's latest loaded snapshot, excludes other pages, and is separate from the live total above. It adds no requests or settings.

Select **Show totals in bytes** beside Downloaded/Uploaded to inspect whole-byte counters with locale-specific digit grouping instead of rounded KiB/MiB/GiB values. Both totals update immediately and keep the selected format during polling. Reloading restores human-readable units; rates, charts and memory keep their usual units. Missing, invalid or larger-than-safe-integer counters display “—”.

Use **Reset displayed totals** beside Downloaded/Uploaded to measure traffic from the latest successful sample: both displayed totals start at zero and increase on subsequent polls. **Since reset (this page)** identifies this view; **Show core totals** or reloading restores the core totals. This measurement is local to the page, requires no core restart, and leaves rates, chart history, connections and other viewers unchanged. Reset is unavailable before a valid sample or after a failed read; recovery retains the baseline. If either core counter decreases, the measurement ends and a notice explains that core totals are shown again.

In **Proxy Groups**, use **Copy proxy name** beside a node to copy its exact name, or **Copy group selection** in a group header to copy a quoted `"group": "selection"` line for troubleshooting notes. Selection copies use the last displayed snapshot and are disabled when no selection is available; they describe the immediate group choice, which can itself be another group. These local actions require no extra privileges or settings and do not change routing. If clipboard access is unavailable (including HTTP or denied permission), a read-only text field opens with the text selected for manual copying. Only the names are included, exactly as displayed; configuration credentials are not fetched.

**Pause statistics** on the overview stops automatic reads of traffic rates, totals, connection counts, core version and runtime mode so you can inspect the displayed values. **Resume statistics** refreshes immediately when no request is already in flight and leaves a gap in traffic history instead of averaging across the pause. In-flight reads may finish, and explicit actions (such as changing mode or closing a connection) can still refresh their results without restarting automatic polling. Proxy groups, service status, current forwarding and process memory continue updating independently. Pause lasts only for this page visit; reopening or reloading the page restores automatic polling.

**Experimental compact overview (default off):** Enable **Compact overview (experimental)** at the top of the overview to fit more metrics and proxy groups on screen. It reduces card spacing and chart height, with three proxy-group columns on wide screens and one on phones. All status information and controls remain available. This browser stores only the enabled layout preference; disabling removes it. If browser storage is unavailable, the toggle still works for the current page. It does not change appliance settings or polling.
**Experimental automatic latency tests (default OFF):** Under **Proxy Groups**, enable **Automatically test latency on overview load (experimental)**. This starts one sweep when groups are available and repeats once on each overview visit while enabled. The opt-in is stored in this tab's session storage; if storage is blocked, it applies only to the current page. Each distinct concrete proxy shown in the groups is tested once, with at most three requests in flight; nested groups and built-in actions such as DIRECT/REJECT are excluded. Probes use the existing latency-test endpoint and require the operate privilege. Progress and failures appear above the groups; polling does not repeat or retry the sweep. Disable the checkbox to opt out. Disabling, hiding or leaving the page stops queued tests while active requests finish; reload to run a stopped sweep again. No service, routing or YAML settings are changed.

Each proxy row also shows up to **10 recent latency measurements** supplied by the controller, oldest to newest. Dots show successful tests; crosses mark timeouts and unknown measurements leave gaps. Each sparkline scales independently, so use the hover values (also available to screen readers) to compare proxies. The horizontal axis is test order, not elapsed time. Existing node/group latency-test buttons refresh the results; displaying history sends no additional probes and stores nothing in the browser. Untested proxies show a dash. History may reset when the core restarts or configuration reloads.

The overview's **Client traffic** table shows the top ten source IPs by combined download and upload bytes on currently active connections, plus each client's connection count. It combines ports and protocols for the same IP, includes an unknown-source bucket, and refreshes with the overview independently of connection-table searches or pagination. These are active-connection lifetime counters, not rates or per-device usage history: closing a connection removes its bytes, and the source IP is the address Mihomo sees (which may reflect NAT). Unavailable data is labeled separately from an empty snapshot.

**Active Connections** supports scoped search: choose **All fields**, **Address**, **Host**, or **Process** in **Search connections in**, then type in the table search box. Address searches source/destination IPs and ports (including IPv6); Host also searches sniffed names; Process searches the reported name and full path. Hover over a process to see its path; a dash means Mihomo did not report process metadata (common for forwarded LAN traffic). Search uses case-insensitive text terms, with every space-separated term required, across the complete current connection list before pagination. Clear the search box to restore all rows; page reload resets the scope. This read-only feature requires no configuration or experimental flag. Traffic totals remain global, and **Close all** still closes all connections, including hidden matches.
In **Active Connections**, filter the table and choose **Close visible** to close only the connections displayed on the current page. Confirm the captured count; hidden rows, other pages and connections arriving after the click are excluded, even if the search or page changes during confirmation. Requests run at most three at a time, with completed and failed/unconfirmed counts, followed by a table refresh. Connections that already ended may be reported as failed; applications may reconnect. **Close all** still closes every active connection regardless of the filter.
The overview **Mode** selector includes a short explanation of the displayed choice: rule-based routing follows matching rules, global mode uses the GLOBAL group selection (which may itself be DIRECT), and direct mode connects without a proxy. The hint updates when you select a mode or the overview refreshes its mode value. It explains the choice, not whether a requested switch succeeded; failures still appear in the action status. These modes affect traffic handled by Mihomo, not every connection through the firewall.

Each **Proxy Groups** card shows **Members: N**, the number of direct entries reported by the controller, including nested groups and DIRECT/REJECT choices. Empty groups show zero. Counts refresh with the group list, making changes after subscription updates easy to spot; they do not indicate how many proxies are healthy.

In **Proxy Groups**, **Hide proxy until reload** hides that exact name across groups for this page visit only. Selected entries still show when they match the name filter. Use **Show hidden proxies** to inspect and restore individual names, or **Restore all proxies** to clear the list. Hidden-name counts do not change the name filter, favorites, proxy selection, routing or the scope of group latency tests. No setting is stored.

The **Proxy latency summary** counts each proxy once across all groups using the latest successful group response. It indicates positive delay, nonpositive recorded results (without guessing the cause), and untested or unknown results, not live availability. Nested groups and built-in routing actions are excluded. The name filter does not affect the summary; a failed or malformed read shows status unavailable. No extra requests or tests are made.

Use **Test all groups** in **Proxy Groups** to manually test every member in the displayed group cards, including collapsed groups. Shared names are tested once per run, with at most three requests in flight. The progress line shows completed tests and failures; results refresh when the batch finishes. Node, group and all-group test controls stay disabled during the batch. The action is unavailable until groups load successfully or when there are no members. It does not select proxies, change settings or schedule automatic tests.

**No usable proxies** highlights a group whose reported candidates are all unavailable, including through nested groups: no members, only REJECT/REJECT-DROP, failed latest latency results (zero or negative), or cycles with no exit. DIRECT counts as usable; untested, missing or invalid results remain unknown and suppress the warning. Nested groups are evaluated across their members, not just their current selection. The warning stays visible when collapsed and refreshes with controller polling or latency tests. It uses the last reported results, not a live connectivity guarantee, and does not run probes or change routing. Hover over the badge for its interpretation.

Use the chevron beside a group's member count to **Collapse group** or **Expand group** (also available with Enter or Space). Collapsing folds away the member list while keeping the group name, type, count, favorite and group latency-test controls visible. Choices are remembered by exact group name for this page visit, including after polling, reordering or controller recovery; reloading starts with all groups expanded. Collapsing does not change routing or selections, and group latency tests still test every member.

During a node or group latency test, use **Stop tests** in the **Proxy Groups** header to skip the remaining queued probes. Up to three requests already running finish normally; their results are retained and the group list refreshes afterward. The status shows completed/total, failed and skipped counts. New tests remain disabled until those active requests return. Stopping tests does not change proxy selections or routing.

In **Proxy Groups**, click the star beside a group to pin its card first, or beside a proxy to pin it first in every group containing it. Click again to restore its normal order. Stars do not change the selected proxy or routing. Favorites are remembered by exact name in this browser for this WebGUI address (shared by users of the same browser profile); clearing site data removes them. Missing nodes retain their stars if the same names return after a subscription update. If browser storage is unavailable, stars work for the current page visit and a notice explains that they could not be saved.

Use **Proxy Groups → Node order** to sort proxies by **Name (A–Z)** or **Name (Z–A)** within each group. Names follow browser locale collation, ignore case, and compare numbers naturally (Node 2 before Node 10); equal names keep configuration order. Favorites stay first, with each section sorted separately. **Configuration order** restores the original order within those sections. Sorting applies to subsequent polls, sends no requests, and does not change selections or group order. Reloading resets it to configuration order.

Use **Last delay: fastest first** or **Last delay: slowest first** in the same menu to sort by the controller’s last recorded measurements, which may be stale. For both options, favorites stay first; within each section, ties keep configuration order, and failed or untested nodes stay last. These two options only change the display: the existing full-group test keeps the same probe order it uses with **Configuration order**.

In **Proxy Groups**, use the pencil beside a proxy to **Edit local note** (up to 160 characters), for example “backup for video calls” or “maintenance on Friday”. **Save note** updates every occurrence of that exact proxy name; **Cancel** discards the draft, and saving an empty note removes it. Drafts survive polling. Notes persist in this browser profile for this WebGUI address, are shared with other users of that profile, and are removed by clearing site data. Missing names retain their notes if they return; renamed proxies do not inherit notes. Notes are not sent to Mihomo or included in configuration backups. If storage is unavailable, a notice explains that changes, including removals, last only for this page visit.

Current forwarding is a read-only view of loaded PF rules, preserving address families, directions, port limits and exceptions. Rule order and core policies still affect traffic; DNS paths describe configuration and require a client query to confirm reachability. Process memory reports the core's RSS.

In **Current forwarding → Rule details** on Overview or Policy Routing, click **Copy match** beside a destination to copy that row's observed `from <source> to <destination and conditions>` text. Exclusions, port sets and IPv6 text are preserved. This is a match fragment, not a complete PF rule: interface, protocol, direction and next hop remain in the table. A success message confirms the clipboard write; if the browser blocks it (including on HTTP), a prompt offers the same text for manual copying. Copying makes no configuration changes or extra API requests.

In **Active Connections**, use the copy icon beside **Source** for the source IP or beside **Host** for the destination IP. Hover or focus the button to identify its address. Copying uses the IP reported by Mihomo, without a port or IPv6 brackets; it does not resolve hostnames or substitute the displayed host. Missing IPs have no copy button. If the browser blocks clipboard access (including on HTTP), a selected read-only field lets you copy manually. This also works with view-only privileges and makes no extra API requests.

In **Overview → Proxy Groups**, choose **Export selections (JSON)** to read all current group selections into a selected, read-only snippet for notes or troubleshooting. Press **Ctrl+C / Command+C** to copy it. The report contains a capture time, group names, types and selected member names; `null` means no single selection was reported. Automatic selections may change afterward; export again to refresh. Exporting does not change routing or save a restorable snapshot.

In **Active Connections**, use the **Details** button on a row to inspect its destination IP/port, matched rule and rule value, and proxy chain. The dialog shows a snapshot from that row; refresh the connection list and reopen details for newer data. Missing fields appear as `—`.

**Policy Routing → Runtime rules** searches the core's loaded top-level rules by type, rule value (such as a domain or rule-set name), or proxy target. Search is a case-insensitive literal substring across the entire snapshot; combine it with the rule-type selector to narrow results. Results retain their original positions and show 50 rows per page. Clear filters restores the full list. The snapshot loads on first opening the tab; use Refresh after changing the running configuration. A failed refresh retains the previous snapshot with a warning. This read-only feature needs the existing Mihomo view privilege and no feature flag. It does not simulate routing, expand rule-set contents, or read unapplied YAML changes.

**Proxy selection snapshots:** In Overview → Proxy Groups, enter a name and click **Save snapshot** to capture current manual `Selector` group selections. Choose a saved name and click **Restore snapshot** to preview and confirm changes, or **Delete snapshot** to remove it. Up to 20 snapshots persist in this browser for the current firewall origin; clearing browser storage removes them. Names must be unique and 1–80 characters. Snapshots contain only group/member names, not credentials or configuration files, and exclude automatic groups. Restore reads current groups first and refuses all changes if a saved group/member is missing or its type changed. Unchanged selections and groups added since capture are left alone. Writes run sequentially and stop on failure; earlier changes remain active and the failed selection may be unconfirmed. Restore is not atomic across groups or other operators; check the refreshed groups before retrying. No restore runs automatically.

Experimental automatic proxy selection defaults **OFF**. In Overview → Proxy Groups, enable **Automatically select the fastest proxy after a group test (experimental)**, then click a Selector group’s test button. After the bounded latency test completes, the page selects the lowest positive latency from that run; equal latency keeps the current selection. Failed/untested nodes, direct/reject targets and nested groups cannot win. Individual node tests and ordinary polling never switch groups. The option resets on reload and writes no plugin settings. Disabling it, hiding/leaving the page, manually selecting a node, or a changed group cancels a pending switch. A switch already submitted cannot be cancelled. This is a live runtime selection, not a continuous background service; other clients can still change the group between the final read and write.

After manually choosing a node in a **URLTest** or **Fallback** group, click **Resume automatic selection** on its card in **Proxy Groups** to clear that override. Mihomo resumes the group's configured policy and the overview refreshes the actual selection; the selected node may stay the same. This uses the core's reset API, including its selection-cache handling, without editing YAML or restarting the service. The button appears only for groups reporting a manual override. Selector groups are excluded: the core's reset API does not restore their `default-selected` value. Failed resets are reported and can be retried.

**Core uptime** on the overview shows the verified core process age as hours:minutes:seconds (hours can exceed 24), sampled with Current forwarding every 30 seconds. **Last successful start / reload** shows the browser-local time of the last service start or restart that passed the rc.d startup check; this plugin applies reloads by restarting the core. The record survives stops and failed starts during the current boot, resets on reboot, and is unavailable until the first recorded success after upgrading. Saving a file does not update it; reloads through an external controller are not tracked. A stopped or unidentified core has no uptime, and a failed runtime read clears both timing values until polling recovers. These are observations, not health checks.

![Mihomo overview with live metrics and traffic history](docs/assets/overview.png)

These screenshots show the actual interface with sensitive information blurred by a local script. Colors inherit the system theme; pictured configuration values illustrate the interface only.

## Requirements

| Component | Current version / target |
| --- | --- |
| Plugin | `1.1.0` |
| OPNsense | `26.7` series |
| Build environment | FreeBSD `15.1`, `amd64` |
| Mihomo core | `1.19.31-vincent` |
| Package dependencies | `curl`, `jq` |

Other system versions and architectures require separate validation. Pinned sources and checksums are recorded in the [core manifest](packaging/freebsd/binary-source.json) and [Geo data manifest](packaging/freebsd/geodata-source.json).

## Installation

### Install a build artifact

1. Open [GitHub Actions](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml), select a successful build and download its `os-mihomo-freebsd15-amd64` artifact.
2. Extract it and place `os-mihomo.pkg`, `os-mihomo-repository.tar.gz` and `SHA256SUMS` together on the target system. The artifact also includes a `package-files.txt` inventory.
3. From that directory, verify and install as an administrator:

```sh
# Verify both archives; stop if either checksum fails.
while read -r expected file; do
    sha256 -c "$expected" "$file" || exit 1
done < SHA256SUMS

pkg install -y curl jq
pkg add os-mihomo.pkg

# Load the plugin's backend actions into OPNsense.
service configd restart
```

**Fresh installations disable autostart and do not start Mihomo.** Installation hooks do not create interfaces or firewall rules, or change routing or DNS. Configuration ships as `.sample` files and is copied only when the corresponding live file is absent. Existing configuration and autostart settings are preserved.

The bundled YAML contains example nodes and credentials. Complete the initial configuration below before starting the service.

### Distribute through the plugin manager

Maintainers can extract the repository archive to a static file server, preserving its ABI subdirectory. Edit the included `os-mihomo.conf` so its `url` points to the directory containing `meta.conf`, then place the configuration in `/usr/local/etc/pkg/repos/` on the target system.

After refreshing repository metadata, manage `os-mihomo` under **System → Firmware → Plugins**. Supply your own repository URL: the build produces repository files but does not provision a hosted package source. See [CI/CD](docs/ci-cd.md).

## Initial configuration

1. **Prepare a working configuration.** Edit Mihomo YAML in Settings, or enter subscription details and run an update from Subscription. Check nodes, proxy groups, the controller secret and listening address. A loopback listener is sufficient for the WebUI.
2. **Choose which values the form manages.** YAML fields have lock icons. A locked field preserves the file value on Apply; an unlocked field allows the form to write it. Fixed fields cannot be edited. Plugin settings such as autostart and subscriptions are separate from these YAML locks.
3. **Validate before starting.** Use configuration validation and comparison, and review TUN, automatic routing and DNS options. Then start Mihomo using the service controls. Starting or stopping the service is separate from enabling autostart.
4. **Add routing policies as needed.** Select an interface and proxy group, preview the changes, then apply. Asking the plugin to create firewall rules also involves OPNsense interface, gateway and firewall configuration. With manual management, you must arrange for traffic to reach Mihomo yourself.
5. **Check the running result.** Use the overview, active connections, DNS status and logs. Form, file and runtime values can differ; Configuration comparison shows those differences.

Once network policies are active, affected traffic may depend on Mihomo continuing to run. Remove that dependency before stopping the service or uninstalling the plugin.

![Routing policies with interface rules, preview controls and configuration history](docs/assets/routing.png)

## Configuration and maintenance

### Forms, YAML and runtime state

Saved form settings, YAML on disk and the core's running configuration are managed separately. Apply writes permitted fields to the file and synchronizes plugin settings. Saving a file does not mean the running core has loaded it; explicitly request a restart when needed.

The advanced YAML editor starts in read-only mode. Unlock it to edit and review changes before saving. The server validates the new configuration and backs up the old file before replacing it. DNS status and Configuration comparison are read-only views.

In Configuration comparison, **Export comparison (JSON)** downloads all rows from the last successful read, including the collection time and runtime availability. The differences-only filter does not limit the export. Secret values are omitted; addresses and other displayed settings remain. The report captures saved form, file and observed runtime values, not unsaved edits, and is not a restorable configuration backup. Refresh to collect a new snapshot; export is unavailable while loading or after a failed read.

![Configuration comparison across form, file and runtime values](docs/assets/configuration-comparison.png)

### Write coordination and privileges

Settings, YAML, policy, subscription installation and restoration share a writer lock. Pages submit their original SHA-256 revision; stale submissions are rejected. Reload and review changes before retrying. Settings revisions include the OPNsense configuration file, so another administration page may also require a reload. Rule enable/delete operations remain immediate actions on the current UUID.

Candidates are validated in unique files on the target filesystem, then the actual previous bytes are backed up before atomic replacement of each target. Settings group YAML, subscription env and autostart files; policy groups YAML and its subscription template. Recoverable commit errors restore targets already replaced. Configurations and backups use `0600`; backups named `<file>.bak.<time>_<random>` retain the latest 20 per file. Configuration history validates restored YAML and first backs up the current file. Cross-file transactions do not guarantee all-or-nothing recovery after power loss or forced process termination; inspect both targets against their backups in that case.

Action `state` distinguishes `unchanged`, `completed`, `accepted`, `failed` and `partial`. Cron and service reloads occur after the file transaction; failures report partial completion, and failed Cron reloads remain pending for retry. An accepted restart does not prove service readiness. Logs mask URLs and common secret fields; configuration editors and history still expose their content to authorized configuration administrators.

Settings also shows the latest 10 apply/reapply attempts made on the open page, with start times, submitted field names and outcomes. This list distinguishes save failures, partial applies, unchanged files, accepted restarts and unconfirmed responses. It retains no field values or backend messages and makes no extra requests. Reloading clears it; YAML edits and other operators' actions are not included. Submitted field names are not proof that those files changed.

New OPNsense privileges separate `Mihomo (view)`, `Mihomo (operate)` and `Mihomo (configure)` for status/redacted logs, runtime control and configuration/credentials. Combine as needed. Existing full `Mihomo` grants remain compatible. Native settings model save/import retain the existing full-admin requirement. Read-only users cannot select proxies, change mode, close connections or write settings. View privileges do not grant raw YAML, subscription credentials or backup contents.

### Subscription updates

Subscription updates regenerate `config.yaml` from the subscription template and can overwrite manual edits. Changes that must survive updates should also be reflected in the template. Download or validation failure preserves the old configuration. Changes to configuration, template or env during download also reject installation. WebUI updates default to writing files only; restart is explicitly selected. CLI/scheduled updates retain their existing restart behavior. Check the lightweight task status and subscription log after submission.

The compatibility converter default is `https://subconverters.com/sub`. With a converter, the router sends the **complete subscription URL, including its token**, to that service so it can fetch and convert node data. The controller secret is added locally and is not a converter parameter. The converter is a third-party trust boundary; full requests and secrets are not logged. In root-owned `/usr/local/etc/mihomo/sub/env`, choose one of these shell variables and retain mode `0600`:

```sh
# Provider supplies Clash YAML containing proxies; bypass conversion.
MIHOMO_CONVERTER_URL='direct'
# Or choose a trusted/self-hosted HTTPS converter:
# MIHOMO_CONVERTER_URL='https://converter.example.com/sub'
```

Direct mode still downloads from the provider. It extracts nodes and combines them with the local template instead of adopting subscription rules or groups.

| File | Purpose |
| --- | --- |
| `/usr/local/etc/mihomo/config.yaml` | Mihomo configuration file |
| `/usr/local/etc/mihomo/sub/template_config.yaml` | Subscription generation template |
| `/usr/local/etc/mihomo/sub/env` | Subscription parameters and credentials |
| `/etc/rc.conf.d/mihomo` | Autostart setting |
| `/var/log/mihomo.log` | Core log |
| `/var/log/mihomo_sub.log` | Subscription task log |

### Upgrades, migration and removal

Back up the OPNsense configuration and Mihomo configuration files before upgrading. When migrating from another package with the same name, inspect its uninstall hooks for cleanup actions that could affect existing network settings.

This version retains user configuration and network settings on removal and does not stop the service automatically. Remove dependent network policies and stop Mihomo before uninstalling. Retained configuration is available for later recovery.

### Troubleshooting

- **The page opens but has no runtime data:** Check that Mihomo is running, its controller is reachable over loopback, and the port and secret in the current file match the running instance.
- **A form change did not update the file:** Check the field's lock. Only unlocked YAML fields are written by the form.
- **The file changed but runtime values are old:** Configuration comparison exposes this difference. Review the changes, then reload the service configuration.
- **Backend actions are unavailable after installation:** Ensure `service configd restart` has been run, then refresh the WebGUI.

## Development and builds

The repository root is the plugin tree. `src/` mirrors installation paths on the target system.

| Directory | Contents |
| --- | --- |
| `src/usr/local/opnsense/mvc/app/` | MVC models, controllers and Volt views |
| `src/usr/local/opnsense/scripts/mihomo/` | Plugin backend scripts |
| `src/usr/local/opnsense/service/conf/actions.d/` | configd action definitions |
| `packaging/freebsd/` | Package metadata, hooks and asset provenance |
| `locales/` | gettext template and translations |
| `tests/`, `tools/` | Regression checks and maintenance tools |

Pages use `/ui/mihomo/*`; API endpoints use `/api/mihomo/*`.

Source checks require Python 3, Node.js, PHP and a POSIX shell:

```sh
python3 tools/check_publication.py
python3 tools/validate.py
```

Build on FreeBSD 15 amd64 with `make`, `pkg`, `tar`, `xz`, `sha256`, and either `fetch` or `curl`:

```sh
make package   # Produces dist/os-mihomo.pkg
make repo      # Produces dist/repo/<ABI>/
```

These commands build artifacts without installing the plugin or executing package hooks. CI builds and inspects packages in an isolated FreeBSD environment. A matching `v<version>` tag triggers a draft release. See [CI/CD](docs/ci-cd.md) for the complete workflow.

Builds also require Python 3 and Git. `SOURCE_DATE_EPOCH` defaults to the source commit time; archive ordering, ownership and timestamps are normalized, and CI compares two independent package builds byte for byte. Releases include source/toolchain records in `build-info.json`. New tag builds produce GitHub attestations, verified with `gh attestation verify os-mihomo.pkg --repo Thweki/os-mihomo`; older releases do not acquire attestations retroactively. Repository signing supports `REPO_SIGNING_KEY`, `REPO_PUBLIC_KEY` and `REQUIRE_SIGNED=yes`. Production keys, trusted public-key distribution and HTTPS hosting require operator configuration; see the CI/CD guide.

### Translation

Edit `locales/<locale>.po` using `locales/os-mihomo.pot`, then generate and check the catalogs:

```sh
python3 tools/build_locales.py
python3 tools/build_locales.py --check
```

Commit generated catalogs alongside translation changes. The plugin uses its own gettext domain without modifying OPNsense system catalogs. Missing translations fall back to system translations or English.

## Credits

This project independently develops a native WebUI on top of the `os-mihomo 1.0.4` assets and packaging from [Opnwall/OPNsense-repo](https://github.com/Opnwall/OPNsense-repo).

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo): Mihomo core.
- [Vincent-Loeng/clash-meta](https://github.com/Vincent-Loeng/clash-meta): the FreeBSD core build used here.

Source files and third-party components retain their original copyright and license notices.
