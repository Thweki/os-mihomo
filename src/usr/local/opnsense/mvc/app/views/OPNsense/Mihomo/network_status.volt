{% set lang = mihomoLang %}
<script>
$(document).ready(function () {
    const $root = $(document.getElementById({{ network_id | json_encode }}));
    let pending = false, snapshot = null, dns = [];
    function text(value) { return MihomoUI.decodeApiText(value); }
    function render() {
        if (!snapshot) { return; }
        const $body = $root.find('.network-rows').empty();
        const allRules = snapshot.rules || [];
        const directions = {in: {{ lang._('Incoming') | json_encode }}, out: {{ lang._('Outgoing') | json_encode }}, any: {{ lang._('Any direction') | json_encode }}};
        const interfaces = (snapshot.interfaces || []).slice();
        if (allRules.some(rule => !interfaces.some(iface => iface.device === rule.device))) {
            interfaces.push({interface: '', device: '', description: {{ lang._('Other rule scopes') | json_encode }}});
        }
        interfaces.forEach(function (iface) {
            const rules = allRules.filter(rule => iface.device ? rule.device === iface.device
                : !(snapshot.interfaces || []).some(item => item.device === rule.device));
            const $row = $('<tr>').append($('<td>').append($('<strong>').text(text(iface.description)))
                .append($('<small class="text-muted">').css('display', 'block').text(text(iface.interface))));
            ['tcp', 'udp'].forEach(function (protocol) {
                const $cell = $('<td>');
                if (!snapshot.rules_available) {
                    $cell.text({{ lang._('Unavailable') | json_encode }});
                } else {
                    const values = [];
                    rules.filter(rule => rule.protocols.includes(protocol) || rule.protocols.includes('any')).forEach(function (rule) {
                        const value = rule.family + ' · ' + directions[rule.direction] + ' · ' + (rule.ports === '*' ? {{ lang._('All destination ports') | json_encode }} : text(rule.ports));
                        if (!values.includes(value)) { values.push(value); }
                    });
                    if (!values.length) { $cell.addClass('text-muted').text({{ lang._('No TUN rule observed') | json_encode }}); }
                    values.forEach(value => $cell.append($('<div>').text(value)));
                }
                $row.append($cell);
            });
            const item = dns.find(item => item.interface === iface.interface);
            const paths = {mihomo: 'Mihomo', unbound: 'Unbound', manual: {{ lang._('Manual') | json_encode }},
                pending: {{ lang._('Not confirmed') | json_encode }}, none: {{ lang._('Not confirmed') | json_encode }}};
            $row.append($('<td>').text(item ? (paths[item.path] || {{ lang._('Unavailable') | json_encode }}) : '—'));
            $body.append($row);
        });
        if (!interfaces.length) { $body.append($('<tr>').append($('<td colspan="4">').text({{ lang._('No interface data available.') | json_encode }}))); }
        const $details = $root.find('.network-details-body').empty();
        allRules.forEach(function (rule) {
            const $row = $('<tr>');
            [rule.device || '—', rule.family + ' / ' + directions[rule.direction] + ' / ' + rule.protocols.join(', '), rule.source,
                rule.destination, rule.next_hop].forEach(value => $row.append($('<td>').text(text(value))));
            $details.append($row);
        });
        if (!allRules.length) { $details.append($('<tr>').append($('<td colspan="5">').text(snapshot.rules_available
            ? {{ lang._('No TUN forwarding rules were observed in the loaded PF ruleset.') | json_encode }}
            : {{ lang._('The loaded PF ruleset could not be read.') | json_encode }}))); }
    }
    function refresh() {
        if (pending) { return; }
        pending = true;
        $root.find('.network-refresh').prop('disabled', true);
        ajaxGet('/api/mihomo/dashboard/runtime_status', {}, function (data, status) {
            pending = false;
            $root.find('.network-refresh').prop('disabled', false);
            if (status !== 'success' || !data || data.status !== 'ok') {
                $root.find('.network-read-state').text({{ lang._('Read failed. The last result is retained.') | json_encode }});
                return;
            }
            snapshot = data;
            render();
            $root.find('.network-read-state').text({{ lang._('Updated') | json_encode }} + ' · ' + new Date(data.observed_at * 1000).toLocaleTimeString());
            $(document).trigger('mihomo:runtime', [data]);
        });
        ajaxGet('/api/mihomo/settings/dns_status', {}, function (data, status) {
            if (status === 'success' && data && data.status === 'ok') { dns = data.interfaces || []; render(); }
        });
    }
    $root.find('.network-refresh').click(refresh);
    $root.find('.network-details-toggle').click(function () {
        const $details = $root.find('.network-details');
        $details.toggleClass('hidden');
        $(this).attr('aria-expanded', !$details.hasClass('hidden'));
    });
    refresh();
    setInterval(function () { if (!document.hidden) { refresh(); } }, 30000);
});
</script>
<div class="content-box" id="{{ network_id }}" style="padding:14px; margin-bottom:15px;">
    <div style="display:flex; align-items:center; flex-wrap:wrap; gap:10px; margin-bottom:12px;">
        <b>{{ lang._('Current forwarding') }}</b>
        <small class="network-read-state text-muted" role="status">{{ lang._('Loading …') }}</small>
        <span style="margin-left:auto; display:flex; flex-wrap:wrap; gap:8px; align-items:center;">
            <a href="/ui/mihomo/settings#compare">{{ lang._('Configuration comparison') }}</a>
            <button type="button" class="network-details-toggle btn btn-default btn-sm" aria-expanded="false">{{ lang._('Rule details') }}</button>
            <button type="button" class="network-refresh btn btn-default btn-sm">{{ lang._('Refresh') }}</button>
        </span>
    </div>
    <div class="table-responsive"><table class="table table-condensed table-hover">
        <thead><tr><th>{{ lang._('Interface') }}</th><th>TCP → TUN</th><th>UDP → TUN</th><th>{{ lang._('Configured DNS path') }}</th></tr></thead>
        <tbody class="network-rows"><tr><td colspan="4">{{ lang._('Loading …') }}</td></tr></tbody>
    </table></div>
    <p class="text-muted">{{ lang._('Loaded PF rules are shown here. Rule order, exceptions and core policies still affect traffic. DNS paths describe the configuration, not a client query test.') }}</p>
    <div class="network-details hidden table-responsive">
        <table class="table table-condensed table-hover"><thead><tr>
            <th>{{ lang._('Device') }}</th><th>{{ lang._('Protocol') }}</th><th>{{ lang._('Source') }}</th>
            <th>{{ lang._('Destination and conditions') }}</th><th>{{ lang._('Next hop') }}</th>
        </tr></thead><tbody class="network-details-body"></tbody></table>
    </div>
</div>
