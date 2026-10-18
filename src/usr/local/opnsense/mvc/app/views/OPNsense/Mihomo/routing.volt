{#
 # os-mihomo —— 路由策略（把物理接口绑给 mihomo）
 #
 # 页面只保留三样东西：表格（绑定关系）、一行状态、应用/预览/回滚。
 # 「应用」= 写 mihomo 规则 + 同步 OPNsense 网络侧（先弹窗列出变更）。
 #
 # Copyright (C) 2026  os-mihomo contributors
 # All rights reserved. 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 #}

<script>
    $(document).ready(function () {
        let lastPlan = { changes: [], rules: [], warnings: [], state: {} };

        function dialog(title, text, type) {
            BootstrapDialog.show({
                'type': type,
                'title': title,
                'message': $('<pre>').css({
                    'white-space': 'pre-wrap', 'margin': '0', 'border': '0', 'background': 'transparent'
                }).text(decode(text))
            });
        }

        function decode(text) {
            return $('<textarea/>').html(String(text == null ? '' : text)).text();
        }

        /* 绑定状态：只说人话 */
        function stateText(row) {
            if (row.state === 'active') {
                return '{{ lang._('in effect') }}';
            }
            if (row.state === 'pending') {
                return '{{ lang._('apply to take effect') }}';
            }
            if (row.state === 'inactive') {
                return '{{ lang._('TUN off') }}';
            }
            return '{{ lang._('Manual') }}';
        }

        function fillSelect(el, items, keep) {
            const $el = $(el);
            const previous = keep || $el.val();
            $el.empty();
            items.forEach(function (item) {
                $el.append($('<option>').val(item.value).text(item.label));
            });
            if (previous) {
                $el.append($('<option>').val(previous).text(previous + ' *'));
                $el.val(previous);
            }
        }

        /* 一行状态：绑定关系 + 网络侧 */
        function loadState() {
            ajaxGet('/api/mihomo/routing/status', {}, function (data, status) {
                if (status !== 'success') {
                    return;
                }
                const parts = (data.rows || []).map(function (row) {
                    return row.interface + ' → ' + (row.target || 'DIRECT') + ' · ' + stateText(row);
                });
                $('#routeState').text(parts.length ? parts.join('　') : '{{ lang._('nothing bound') }}')
                    .toggleClass('text-muted', parts.length === 0);
                $('#routeNotes').text(
                    data.tun_enabled ? '' : '（' + '{{ lang._('TUN off') }}' + '）'
                );
            });
        }

        $("#{{formGridPolicy['table_id']}}").UIBootgrid({
            search: '/api/mihomo/routing/search_rule/',
            get: '/api/mihomo/routing/get_rule/',
            set: '/api/mihomo/routing/set_rule/',
            add: '/api/mihomo/routing/add_rule/',
            del: '/api/mihomo/routing/del_rule/',
            toggle: '/api/mihomo/routing/toggle_rule/'
        });

        ajaxGet('/api/mihomo/routing/options', {}, function (data, status) {
            if (status !== 'success') {
                return;
            }
            fillSelect(document.getElementById('mihomo.interface'), data.interfaces || []);
            fillSelect(document.getElementById('mihomo.target'), data.targets || []);
        });

        /* 预览：mihomo 规则 + OPNsense 变更 */
        function collectPlan(done) {
            ajaxGet('/api/mihomo/routing/preview', {}, function (preview, s1) {
                if (s1 !== 'success') {
                    return;
                }
                ajaxGet('/api/mihomo/routing/netplan', {}, function (net, s2) {
                    if (s2 !== 'success') {
                        return;
                    }
                    lastPlan = {
                        rules: preview.rules || [],
                        warnings: preview.warnings || [],
                        changes: net.changes || [],
                        state: net.state || {}
                    };
                    done();
                });
            });
        }

        function planText(head) {
            const lines = [];
            lines.push('{{ lang._('mihomo rules') }} (' + lastPlan.rules.length + ')');
            if (lastPlan.rules.length) {
                lastPlan.rules.forEach(function (r) { lines.push('  ' + r); });
            } else {
                lines.push('  —');
            }
            lines.push('{{ lang._('OPNsense changes') }} (' + lastPlan.changes.length + ')');
            if (lastPlan.changes.length) {
                lastPlan.changes.forEach(function (c) { lines.push('  ' + c); });
            } else {
                lines.push('  —');
            }
            if (lastPlan.warnings.length) {
                lines.push('');
                lastPlan.warnings.forEach(function (w) { lines.push('! ' + w); });
            }
            if (head) {
                lines.push('');
                lines.push(head);
            }
            return lines.join('\n');
        }

        $('#previewPolicyAct').click(function () {
            collectPlan(function () {
                dialog('{{ lang._('Preview') }}', planText(''), BootstrapDialog.TYPE_INFO);
            });
        });

        $('#applyPolicyAct').click(function () {
            collectPlan(function () {
                BootstrapDialog.show({
                    'type': BootstrapDialog.TYPE_WARNING,
                    'title': '{{ lang._('Apply') }}',
                    'message': $('<pre>').css({
                        'white-space': 'pre-wrap', 'margin': '0', 'border': '0', 'background': 'transparent'
                    }).text(planText('{{ lang._('Writes the mihomo configuration and, where needed, creates the interface, gateway and firewall rule on OPNsense. config.xml is backed up first.') }}')),
                    'buttons': [
                        { 'label': '{{ lang._('Cancel') }}', 'action': function (d) { d.close(); } },
                        {
                            'label': '{{ lang._('Apply') }}',
                            'cssClass': 'btn-primary',
                            'action': function (d) {
                                d.close();
                                ajaxCall('/api/mihomo/routing/apply', {}, function (r1) {
                                    if (r1['status'] !== 'ok') {
                                        dialog('{{ lang._('Apply failed') }}', decode(r1['message'] || ''), BootstrapDialog.TYPE_DANGER);
                                        return;
                                    }
                                    ajaxCall('/api/mihomo/routing/netapply', {}, function (r2) {
                                        const out = [];
                                        out.push('[mihomo]');
                                        (r1['messages'] || []).forEach(function (m) { out.push('  ' + m); });
                                        out.push('[OPNsense]');
                                        if (r2['status'] === 'ok') {
                                            (r2['messages'] || []).forEach(function (m) { out.push('  ' + m); });
                                        } else {
                                            out.push('  ' + decode(r2['message'] || ''));
                                        }
                                        dialog('{{ lang._('Apply') }}', out.join('\n'),
                                            r2['status'] === 'ok' ? BootstrapDialog.TYPE_SUCCESS : BootstrapDialog.TYPE_DANGER);
                                        loadState();
                                    });
                                });
                            }
                        }
                    ]
                });
            });
        });

        $('#netRollbackAct').click(function () {
            BootstrapDialog.show({
                'type': BootstrapDialog.TYPE_DANGER,
                'title': '{{ lang._('Undo network changes') }}',
                'message': '{{ lang._('Restores the most recent config.xml backup created by this plugin and reloads the firewall.') }}',
                'buttons': [
                    { 'label': '{{ lang._('Cancel') }}', 'action': function (d) { d.close(); } },
                    {
                        'label': '{{ lang._('Undo') }}',
                        'cssClass': 'btn-danger',
                        'action': function (d) {
                            d.close();
                            ajaxCall('/api/mihomo/routing/netrollback', {}, function (data) {
                                dialog('{{ lang._('Undo network changes') }}',
                                    (data['messages'] || []).join('\n'), BootstrapDialog.TYPE_SUCCESS);
                                loadState();
                            });
                        }
                    }
                ]
            });
        });

        $('#refreshPolicyAct').click(loadState);
        loadState();

        /* ------------------------------------------------------------------ *
         * 自检：把测试流量真的送进 TUN，看出口 IP 与命中的规则
         * ------------------------------------------------------------------ */
        $('#selftestAct').click(function () {
            const $btn = $(this).prop('disabled', true);
            ajaxCall('/api/mihomo/routing/selftest', {}, function (data) {
                $btn.prop('disabled', false);
                if (data['status'] !== 'ok') {
                    dialog('{{ lang._('Self test') }}', decode(data['message'] || ''), BootstrapDialog.TYPE_DANGER);
                    return;
                }
                const lines = [];
                (data.results || []).forEach(function (r) {
                    lines.push(r.interface + '  (' + r.source + ' → ' + (r.expected_group || 'DIRECT') + ')');
                    if (r.foreign_ip) {
                        lines.push('  ' + '{{ lang._('exit IP') }}' + ': ' + r.foreign_ip
                            + '   ' + '{{ lang._('rule') }}' + ': ' + (r.foreign_rule || '—')
                            + '   ' + '{{ lang._('Proxy group') }}' + ': ' + (r.foreign_group || '—'));
                    } else {
                        lines.push('  ' + (r.note || 'failed'));
                    }
                    if (r.domestic_rule) {
                        lines.push('  ' + '{{ lang._('domestic') }}' + ': ' + r.domestic_rule);
                    }
                    lines.push('');
                });
                dialog('{{ lang._('Self test') }}', lines.join('\n'), BootstrapDialog.TYPE_INFO);
            });
        });

        /* ------------------------------------------------------------------ *
         * 配置历史
         * ------------------------------------------------------------------ */
        function loadHistory() {
            ajaxGet('/api/mihomo/routing/history', {}, function (data, status) {
                if (status !== 'success') {
                    return;
                }
                const $body = $('#historyBody').empty();
                const rows = data.rows || [];
                if (!rows.length) {
                    $body.append($('<tr>').append($('<td colspan="3">').addClass('text-muted').text('—')));
                    return;
                }
                rows.slice(0, 5).forEach(function (row) {
                    const stamp = row.ts.replace(/(\d{8})_(\d{6})/, '$1 $2');
                    $body.append($('<tr>')
                        .append($('<td>').text(stamp))
                        .append($('<td>').text((row.size / 1024).toFixed(1) + ' KiB'))
                        .append($('<td>')
                            .append($('<button>').addClass('btn btn-xs btn-default __mr').text('{{ lang._('Diff') }}')
                                .click(function () { showDiff(row.ts); }))
                            .append($('<button>').addClass('btn btn-xs btn-default').text('{{ lang._('Restore') }}')
                                .click(function () { confirmRestore(row.ts); }))));
                });
            });
        }

        function showDiff(ts) {
            ajaxGet('/api/mihomo/routing/history_show/' + ts, {}, function (data, status) {
                if (status !== 'success' || data['status'] !== 'ok') {
                    return;
                }
                dialog('{{ lang._('Diff') }} (' + ts + ' → ' + '{{ lang._('current') }}' + ')',
                    decode(data['diff'] || '') || '—', BootstrapDialog.TYPE_INFO);
            });
        }

        function confirmRestore(ts) {
            BootstrapDialog.show({
                'type': BootstrapDialog.TYPE_WARNING,
                'title': '{{ lang._('Restore') }}',
                'message': decode('{{ lang._('Restore this configuration backup? The current file is backed up first and the result is validated with mihomo -t.') }}'),
                'buttons': [
                    { 'label': '{{ lang._('Cancel') }}', 'action': function (d) { d.close(); } },
                    {
                        'label': '{{ lang._('Restore') }}',
                        'cssClass': 'btn-primary',
                        'action': function (d) {
                            d.close();
                            ajaxCall('/api/mihomo/routing/history_restore', { 'ts': ts }, function (data) {
                                dialog('{{ lang._('Restore') }}', (data['messages'] || []).join('\n'),
                                    data['status'] === 'ok' ? BootstrapDialog.TYPE_SUCCESS : BootstrapDialog.TYPE_DANGER);
                                loadHistory();
                            });
                        }
                    }
                ]
            });
        }

        $('#historyRefreshAct').click(loadHistory);
        loadHistory();
    });
</script>

<div class="content-box __mb">
    {{ partial('layout_partials/base_bootgrid_table', formGridPolicy) }}
</div>

<p class="text-muted">
    <span id="routeState"></span><span id="routeNotes"></span>
</p>

<div class="content-box __mb">
    <header class="content-box-header">
        <h3>{{ lang._('Configuration history') }}</h3>
    </header>
    <table class="table table-condensed table-hover">
        <thead>
        <tr>
            <th style="width: 30%;">{{ lang._('Time') }}</th>
            <th style="width: 20%;">{{ lang._('Size') }}</th>
            <th>{{ lang._('Action') }}</th>
        </tr>
        </thead>
        <tbody id="historyBody"></tbody>
    </table>
    <div class="text-right">
        <button class="btn btn-xs btn-default" id="historyRefreshAct" type="button">{{ lang._('Refresh') }}</button>
    </div>
</div>

<section class="grid-bottom-reserve __mt">
    <div class="alert content-box" style="display: flex; align-items: center; margin-bottom: 0;">
        <button class="btn btn-primary __mr" id="applyPolicyAct" type="button">{{ lang._('Apply') }}</button>
        <button class="btn btn-default __mr" id="previewPolicyAct" type="button">{{ lang._('Preview') }}</button>
        <button class="btn btn-default __mr" id="selftestAct" type="button">{{ lang._('Self test') }}</button>
        <button class="btn btn-default __mr" id="netRollbackAct" type="button">{{ lang._('Undo network changes') }}</button>
        <button class="btn btn-default" id="refreshPolicyAct" type="button">{{ lang._('Refresh') }}</button>
    </div>
</section>

{{ partial("layout_partials/base_dialog",['fields':formDialogPolicyRule,'id':formGridPolicy['edit_dialog_id'],'label':lang._('Edit Policy Rule')])}}
