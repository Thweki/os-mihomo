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
                }).text(text)
            });
        }

        function decode(text) {
            return $('<textarea/>').html(String(text == null ? '' : text)).text();
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
                    return row.interface + ' → ' + (row.target || 'DIRECT') + ' · '
                        + '{{ lang._('in effect') }}';
                });
                const notes = [];
                if (!data.tun_enabled) {
                    notes.push('{{ lang._('TUN off') }}');
                }
                if (data.auto_route) {
                    notes.push('{{ lang._('auto-route on') }}');
                }
                $('#routeState').text(parts.length ? parts.join('　') : '{{ lang._('nothing bound') }}')
                    .toggleClass('text-muted', parts.length === 0);
                $('#routeNotes').text(notes.length ? '（' + notes.join('，') + '）' : '');
                $('#routeRules').text((data.rows || []).length);
            });
            ajaxGet('/api/mihomo/routing/netstatus', {}, function (data, status) {
                if (status !== 'success') {
                    return;
                }
                const items = [];
                if (data.interface) {
                    items.push(data.interface + ' / ' + data.device);
                }
                if (data.gateway_present) {
                    items.push(data.gateway_name + ' ' + (data.gateway_ip_configured || ''));
                }
                const names = (data.rules || []).map(function (r) { return r.interface; });
                if (names.length) {
                    items.push('{{ lang._('rule') }} ' + names.join(', '));
                }
                $('#netState').text(items.length ? items.join(' · ') : '{{ lang._('not synchronized') }}');
                $('#netBackups').text((data.backups || []).length);
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
                    }).text(planText('{{ lang._('Writes config.yaml, the subscription template, and (if needed) config.xml. A config.xml backup is created automatically.') }}')),
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
                'title': '{{ lang._('Roll back the OPNsense side') }}',
                'message': '{{ lang._('Restore the most recent config.xml backup and reload the firewall?') }}',
                'buttons': [
                    { 'label': '{{ lang._('Cancel') }}', 'action': function (d) { d.close(); } },
                    {
                        'label': '{{ lang._('Roll back') }}',
                        'cssClass': 'btn-danger',
                        'action': function (d) {
                            d.close();
                            ajaxCall('/api/mihomo/routing/netrollback', {}, function (data) {
                                dialog('{{ lang._('Roll back the OPNsense side') }}',
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
    });
</script>

<div class="content-box __mb">
    {{ partial('layout_partials/base_bootgrid_table', formGridPolicy) }}
</div>

<p class="text-muted">
    <span id="routeState"></span><span id="routeNotes"></span>
    &nbsp;·&nbsp; {{ lang._('OPNsense side') }}: <span id="netState"></span>
</p>

<section class="grid-bottom-reserve __mt">
    <div class="alert content-box" style="display: flex; align-items: center; margin-bottom: 0;">
        <button class="btn btn-primary __mr" id="applyPolicyAct" type="button">{{ lang._('Apply') }}</button>
        <button class="btn btn-default __mr" id="previewPolicyAct" type="button">{{ lang._('Preview') }}</button>
        <button class="btn btn-default __mr" id="netRollbackAct" type="button">{{ lang._('Roll back the OPNsense side') }}</button>
        <button class="btn btn-default" id="refreshPolicyAct" type="button">{{ lang._('Refresh') }}</button>
    </div>
</section>

{{ partial("layout_partials/base_dialog",['fields':formDialogPolicyRule,'id':formGridPolicy['edit_dialog_id'],'label':lang._('Edit Policy Rule')])}}
