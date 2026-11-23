# How routing status is determined

[中文使用指南](usage.md) · [English user guide](usage.en.md) · [Build and CI](ci-cd.md)

The read-only routing and safety readers share `RoutingStatus`. Native floating
rules live at `OPNsense/Firewall/Filter/rules/rule`; their binding comes from
`source_net` and `Mihomo policy (interface)`, because the writer leaves `interface`
empty. The native fields/defaults were checked against the
[OPNsense Filter model](https://raw.githubusercontent.com/opnsense/core/master/src/opnsense/mvc/app/models/OPNsense/Firewall/Filter.xml).
Legacy root `filter/rule` entries remain readable during migration. Disabled
rules, bypass rules, unrelated descriptions and other gateways do not establish
an automatic binding. The policy-net inventory uses the same reader.

Each automatic binding needs a usable saved TUN gateway, its own saved rule and
matching loaded PF evidence. Evidence must match the source IPv4 scope, incoming
device (or a floating scope), address family and current TUN peer. Restricted
protocols/destinations, aliases and unsupported scopes do not confirm full
coverage. Disabled/manual bindings and unreadable PF have distinct states.
“PF rule observed” describes an observation, not reachability or confirmation of
the selected core outbound. Rule order, bypasses and core policies still matter.

Safety warns about configured exposure even without a loaded rule or when the
runtime read fails. It also warns when matching PF forwarding remains after the
saved binding disappears. Legacy/native duplicates produce one interface warning.

## Regression fixtures

`tests/fixtures/routing/` contains a fresh installation, a legacy installation,
a native post-bind/post-migration configuration, and corresponding PF output.
`tests/test_routing_status.php` exercises the actual routing endpoint and safety
report with isolated framework/backend stubs, plus the shared safety reader:

- Fresh install pending, then native binding observed only on its own interface.
- Legacy and migrated native states/warnings agree; mixed inventory deduplicates.
- Saved-only and stale-loaded states; disabled/edited rules and disabled gateways.
- Wrong source, device, peer, direction, family and limited protocol/port scopes.
- Custom source hosts, manual/disabled bindings, TUN off and runtime failures.

The fixtures represent the before/after migration states; they do not execute
migration writes on an appliance. PHP tests run in `tools/validate.py` and the
FreeBSD package CI script. `tests/test_ui.js` checks the actual status renderer.

To run the routing status fixture locally, use `php tests/test_routing_status.php`.
To review results for a specific commit, open its [GitHub Actions run](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml).
