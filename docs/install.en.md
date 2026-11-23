# Install, upgrade and remove os-mihomo

[Back to project home](../README.US.md) · [简体中文](install.md)

## Before you install

- Sign in as an OPNsense administrator and confirm the target is **OPNsense 26.7 on FreeBSD 15 amd64**. Other versions and architectures require separate validation.
- Export the OPNsense configuration under **System → Configuration → Backups**. For an upgrade or migration, also back up Mihomo's YAML, subscription settings and boot setting. Store these backups securely because they contain credentials. [OPNsense configuration backups](https://docs.opnsense.org/manual/backups.html) · [Mihomo configuration files](usage.en.md#configuration-files)
- If `os-mihomo` is already installed from another publisher, read [Migrating from another source](#migrating-from-another-source) first.

Choose one installation path based on your package source.

## Install through the plugin manager

Use this path if your administrator has configured a **trusted signed repository** that provides os-mihomo. This is a third-party plugin and the project currently has no hosted signed feed. For your own deployment, the repository maintainer sets up HTTPS and distributes the trusted public key before enabling the feed on appliances. [Signed repository setup](ci-cd.md#optional-signed-package-repository)

1. Open **System → Firmware → Status** and check for updates to refresh the package catalogue.
2. Open **System → Firmware → Plugins**, select **Show community plugins** if needed, and search for `os-mihomo`.
3. Verify that the name, version and source are the ones you expect, then install. If more than one source offers the same name, resolve the source before proceeding.

[OPNsense plugin management documentation](https://docs.opnsense.org/manual/firmware.html#plugins)

## Install a single package from Releases

1. Download `os-mihomo.pkg` and the matching `SHA256SUMS` from the [latest project release](https://github.com/Thweki/os-mihomo/releases/latest). These two files are sufficient for a normal installation. Actions artifacts are intended for isolated testing.
2. If the release provides a GitHub build attestation, run `gh attestation verify os-mihomo.pkg --repo Thweki/os-mihomo` on your management computer and confirm the expected release tag. Transfer both files into one directory on OPNsense, enter that directory through the console or SSH, and check the package. Stop if verification fails. [Attestations and checksums](ci-cd.md#reproduce-and-verify)

   ```sh
   expected=$(awk '$2 == "os-mihomo.pkg" { print $1 }' SHA256SUMS)
   [ "${#expected}" -eq 64 ] && sha256 -c "$expected" os-mihomo.pkg
   ```

3. The package depends on `curl` and `jq`. Install any missing dependencies from your existing official OPNsense repository, then run the installation command as an administrator.

   ```sh
   pkg add ./os-mihomo.pkg
   ```

   If pkg reports a platform, dependency or version conflict, check the system and source. Keep the official OPNsense repository and signature verification enabled and resolve the conflict with a compatible package. [FreeBSD pkg add documentation](https://man.freebsd.org/cgi/man.cgi?query=pkg-add&sektion=8)

## Check the installation

1. Confirm that `os-mihomo` is registered under **System → Firmware**. Refresh the WebGUI and open **VPN → Proxy Suite → Mihomo**. If the menu is missing, check the package status and account privileges.
2. If the page opens but backend actions are unavailable after an installation or upgrade, wait for other configuration tasks to finish. In a maintenance window, have an administrator run `service configd restart` to reload OPNsense backend actions, then refresh and retry.
3. On a fresh installation, Mihomo should be stopped and start at boot should be disabled. The package initializes missing configuration files and keeps existing configuration and the boot setting. Its hooks leave firewall, interface, gateway, routing and DNS settings in place. Prepare a valid configuration before starting. [First-time setup](usage.en.md#first-time-setup)

## Upgrade and remove

- **Upgrade.** Back up OPNsense and Mihomo settings, read the release notes and install the target version through your existing trusted channel in a maintenance window. Use the firmware manager for a signed feed, or verify the new release package for standalone installs. Check service status afterwards and restart Mihomo from the WebGUI when you are ready to load a new core or configuration.
- **Remove.** First remove any client forwarding, gateway or DNS dependency on Mihomo and verify normal client routing and DNS. Disable start at boot and stop the service. Then remove it from **System → Firmware → Plugins**. If a manually installed package is registered but the GUI offers no removal action, an administrator can run `pkg delete os-mihomo`. The package hooks retain user configuration and network settings.

### Migrating from another source

Packages with the same name can have different installation and removal scripts. Verify the old publisher and version, review its removal behavior, back up both sets of configuration, and record which network policies depend on Mihomo. Schedule the migration and follow the old publisher's removal or migration instructions before installing this package. Check in particular whether the old scripts remove interfaces, gateways, firewall rules or DNS settings.
