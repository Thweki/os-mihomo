{#
 # os-mihomo —— 路由策略（按接口/源分流）
 #
 # 形态与核心「防火墙: 规则」一致：UIBootgrid 表格 + 行编辑对话框 + 底部应用按钮。
 # 「应用」前会弹窗列出将写入的 mihomo 规则；写入走 configd(root)：
 #   config.yaml 的受管区块（mihomo -t 校验 + 自动备份）+ 订阅模板（避免订阅更新冲掉规则）。
 # 未在此表中出现的接口不会生成任何规则 —— 它们的流量根本不经过 mihomo。
 #
 # Copyright (C) 2026  os-mihomo contributors
 # All rights reserved. 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 #}

<script>
    $(document).ready(function () {
        let currentStatus = {};

        function showMessage(title, message, type) {
            BootstrapDialog.show({
                'type': type,
                'title': title,
                'message': $('<pre>').css({
                    'white-space': 'pre-wrap', 'margin': '0', 'border': '0', 'background': 'transparent'
                }).text(decodeEntities(message))
            });
        }

        /* OPNsense 的 API 会把 > < & 转成实体，展示前还原 */
        function decodeEntities(text) {
            return $('<textarea/>').html(String(text == null ? '' : text)).text();
        }

        function stateLabel(state) {
            const map = {
                'active': '{{ lang._('in effect') }}',
                'pending': '{{ lang._('waiting for the OPNsense side') }}',
                'inactive': '{{ lang._('not reached by mihomo') }}',
                'manual': '{{ lang._('manual routing') }}'
            };
            return map[state] || state;
        }

        /* ------------------------------------------------------------------ *
         * 状态表（只读）：每个接口当前是否真的会经过 mihomo
         * ------------------------------------------------------------------ */
        function loadPolicyStatus() {
            ajaxGet('/api/mihomo/routing/status', {}, function (data, status) {
                if (status !== 'success') {
                    return;
                }
                currentStatus = data;
                const $body = $('#policyStatusBody').empty();
                (data.rows || []).forEach(function (row) {
                    const tone = row.state === 'active' ? 'text-success'
                        : (row.state === 'pending' ? 'text-warning' : 'text-muted');
                    $body.append($('<tr>')
                        .append($('<td>').text(row.interface))
                        .append($('<td>').text(row.source || ''))
                        .append($('<td>').text(row.target || ''))
                        .append($('<td>').addClass(tone).text(stateLabel(row.state)))
                        .append($('<td>').text(row.note || '')));
                });
                if (!(data.rows || []).length) {
                    $body.append($('<tr>').append($('<td colspan="5">').addClass('text-muted')
                        .text('{{ lang._('No policy rule yet. Interfaces without a rule never reach mihomo.') }}')));
                }
                const summary = [];
                summary.push('{{ lang._('TUN') }}: ' + (data.tun_enabled ? '{{ lang._('on') }}' : '{{ lang._('off') }}'));
                if (data.auto_route) {
                    summary.push('{{ lang._('Automatic route takeover is enabled: every interface ends up in the TUN device.') }}');
                }
                summary.push('{{ lang._('Policy routing gateway') }}: ' + (data.gateway ? '{{ lang._('present') }}' : '{{ lang._('absent') }}'));
                summary.push('{{ lang._('Policy routing firewall rule') }}: ' + (data.firewall_rule ? '{{ lang._('present') }}' : '{{ lang._('absent') }}'));
                $('#policyStatusSummary').text(summary.join(' · '));
            });
        }

        /* ------------------------------------------------------------------ *
         * 下拉数据：接口（系统已配置）与代理组（当前 config.yaml）
         * ------------------------------------------------------------------ */
        function fillSelect(el, items, keep) {
            const $el = $(el);
            const previous = keep || $el.val();
            $el.empty();
            items.forEach(function (item) {
                $el.append($('<option>').val(item.value).text(item.label));
            });
            if (previous) {
                $el.append($('<option>').val(previous).text(previous + ' ({{ lang._('not in the current configuration') }})'));
                $el.val(previous);
            }
        }

        ajaxGet('/api/mihomo/routing/options', {}, function (data, status) {
            if (status !== 'success') {
                return;
            }
            fillSelect(document.getElementById('mihomo.interface'), data.interfaces || []);
            fillSelect(document.getElementById('mihomo.target'), data.targets || []);
            if (!data.tun_enabled) {
                $('#policyTunHint').removeClass('hidden');
            }
        });

        /* ------------------------------------------------------------------ *
         * 表格
         * ------------------------------------------------------------------ */
        $("#{{formGridPolicy['table_id']}}").UIBootgrid({
            search: '/api/mihomo/routing/search_rule/',
            get: '/api/mihomo/routing/get_rule/',
            set: '/api/mihomo/routing/set_rule/',
            add: '/api/mihomo/routing/add_rule/',
            del: '/api/mihomo/routing/del_rule/',
            toggle: '/api/mihomo/routing/toggle_rule/'
        });

        /* ------------------------------------------------------------------ *
         * 预览 / 应用
         * ------------------------------------------------------------------ */
        function renderRuleList(rules) {
            if (!(rules || []).length) {
                return '{{ lang._('(no rule)') }}';
            }
            return rules.map(function (line) { return '  - ' + line; }).join('\n');
        }

        function confirmAndApply(preview) {
            let message = $('<div>');
            message.append($('<p>').text('{{ lang._('The following mihomo rules will be written:') }}'));
            message.append($('<pre>').text(renderRuleList(preview.rules)));
            message.append($('<p>').text('{{ lang._('Target files:') }}'));
            message.append($('<pre>').text('/usr/local/etc/mihomo/config.yaml\n/usr/local/etc/mihomo/sub/template_config.yaml'));
            if ((preview.warnings || []).length) {
                message.append($('<p>').addClass('text-warning').text('{{ lang._('Notes') }}'));
                message.append($('<pre>').text(preview.warnings.join('\n')));
            }
            BootstrapDialog.show({
                'type': BootstrapDialog.TYPE_WARNING,
                'title': '{{ lang._('Apply routing policy') }}',
                'message': message,
                'buttons': [
                    {
                        'label': '{{ lang._('Cancel') }}',
                        'action': function (dialogRef) { dialogRef.close(); }
                    },
                    {
                        'label': '{{ lang._('Apply') }}',
                        'cssClass': 'btn-primary',
                        'action': function (dialogRef) {
                            ajaxCall('/api/mihomo/routing/apply', {}, function (data) {
                                if (data['status'] === 'ok') {
                                    let body = (data['messages'] || []).join('\n');
                                    if (data['diff']) {
                                        body += '\n\n{{ lang._('Changes') }}\n' + data['diff'];
                                    }
                                    showMessage('{{ lang._('Routing policy applied') }}', body, BootstrapDialog.TYPE_SUCCESS);
                                    loadPolicyStatus();
                                } else {
                                    showMessage('{{ lang._('Apply failed') }}', data['message'] || '', BootstrapDialog.TYPE_DANGER);
                                }
                            });
                            dialogRef.close();
                        }
                    }
                ]
            });
        }

        function fetchPreview(callback) {
            ajaxGet('/api/mihomo/routing/preview', {}, function (data, status) {
                if (status === 'success') {
                    callback(data);
                }
            });
        }

        $('#previewPolicyAct').click(function () {
            fetchPreview(function (preview) {
                let message = $('<div>');
                message.append($('<p>').text('{{ lang._('config.yaml snippet (managed block):') }}'));
                message.append($('<pre>').text(preview.sample || ''));
                if ((preview.warnings || []).length) {
                    message.append($('<p>').addClass('text-warning').text(preview.warnings.join('\n')));
                }
                BootstrapDialog.show({
                    'type': BootstrapDialog.TYPE_INFO,
                    'title': '{{ lang._('Preview') }}',
                    'message': message
                });
            });
        });

        $('#applyPolicyAct').click(function () {
            fetchPreview(confirmAndApply);
        });

        $('#refreshPolicyAct').click(loadPolicyStatus);

        /* ------------------------------------------------------------------ *
         * 网络侧（OPNsense）：接口 / 网关 / 策略路由规则
         * ------------------------------------------------------------------ */
        function loadNetState() {
            ajaxGet('/api/mihomo/routing/netstatus', {}, function (data, status) {
                if (status !== 'success') {
                    return;
                }
                const rows = [
                    ['{{ lang._('TUN device') }}', data.device + (data.device_up
                        ? ' (' + '{{ lang._('up') }}' + ')' : ' (' + '{{ lang._('down') }}' + ')')],
                    ['{{ lang._('Interface assignment') }}', data.interface || '{{ lang._('absent') }}'],
                    ['{{ lang._('Gateway') }}', (data.gateway_name || '') + ' ' + (data.gateway_present
                        ? '(' + (data.gateway_ip_configured || '?') + ')' : '{{ lang._('absent') }}')],
                    ['{{ lang._('Policy routing rules') }}', (data.rules || []).length
                        ? data.rules.map(function (r) { return r.interface; }).join(', ')
                        : '{{ lang._('none') }}'],
                    ['{{ lang._('config.xml backups') }}', (data.backups || []).length
                        ? (data.backups || []).map(function (b) { return b.split('/').pop(); }).join(', ')
                        : '{{ lang._('none') }}']
                ];
                const $body = $('#netStateBody').empty();
                rows.forEach(function (row) {
                    $body.append($('<tr>')
                        .append($('<td>').css('width', '30%').addClass('text-muted').text(row[0]))
                        .append($('<td>').text(row[1])));
                });
                $('#netStateSummary').text(
                    '{{ lang._('TUN peer address used as gateway') }}: ' + ((data.gateway_ip || '') || '{{ lang._('unknown') }}')
                );
            });
        }

        function applyNet() {
            ajaxCall('/api/mihomo/routing/netapply', {}, function (data) {
                if (data['status'] === 'ok') {
                    let body = (data['messages'] || []).join('\n');
                    if (data['diff']) {
                        body += '\n\n{{ lang._('Changes') }}\n' + data['diff'];
                    }
                    showMessage('{{ lang._('OPNsense side synchronized') }}', body, BootstrapDialog.TYPE_SUCCESS);
                } else {
                    showMessage('{{ lang._('Apply failed') }}', data['message'] || '', BootstrapDialog.TYPE_DANGER);
                }
                loadNetState();
                loadPolicyStatus();
            });
        }

        $('#netPlanAct').click(function () {
            ajaxGet('/api/mihomo/routing/netplan', {}, function (data, status) {
                if (status !== 'success') {
                    return;
                }
                const changes = data.changes || [];
                BootstrapDialog.show({
                    'type': BootstrapDialog.TYPE_INFO,
                    'title': '{{ lang._('Planned OPNsense changes') }}',
                    'message': $('<pre>').text(
                        (changes.length ? changes.join('\n') : '{{ lang._('nothing to do') }}')
                        + '\n\n' + '{{ lang._('TUN peer address used as gateway') }}: '
                        + (((data.state || {}).gateway_ip || '') || '{{ lang._('unknown') }}')
                    )
                });
            });
        });

        $('#netApplyAct').click(function () {
            ajaxGet('/api/mihomo/routing/netplan', {}, function (data, status) {
                if (status !== 'success') {
                    return;
                }
                const changes = data.changes || [];
                let message = $('<div>');
                message.append($('<p>').text('{{ lang._('The following OPNsense changes will be made:') }}'));
                message.append($('<pre>').text(changes.join('\n')));
                message.append($('<p>').addClass('text-warning').text(
                    '{{ lang._('This modifies /conf/config.xml (interface, gateway, firewall rule) and reloads the firewall. Interfaces without a row are not touched. A backup of config.xml is created automatically and can be rolled back from this page.') }}'
                ));
                BootstrapDialog.show({
                    'type': BootstrapDialog.TYPE_WARNING,
                    'title': '{{ lang._('Synchronize OPNsense side') }}',
                    'message': message,
                    'buttons': [
                        { 'label': '{{ lang._('Cancel') }}', 'action': function (d) { d.close(); } },
                        {
                            'label': '{{ lang._('Apply and reload the firewall') }}',
                            'cssClass': 'btn-primary',
                            'action': function (d) { d.close(); applyNet(); }
                        }
                    ]
                });
            });
        });

        $('#netRollbackAct').click(function () {
            BootstrapDialog.show({
                'type': BootstrapDialog.TYPE_DANGER,
                'title': '{{ lang._('Roll back the OPNsense side') }}',
                'message': '{{ lang._('Restore the most recent config.xml backup created by this plugin and reload the firewall?') }}',
                'buttons': [
                    { 'label': '{{ lang._('Cancel') }}', 'action': function (d) { d.close(); } },
                    {
                        'label': '{{ lang._('Roll back') }}',
                        'cssClass': 'btn-danger',
                        'action': function (d) {
                            d.close();
                            ajaxCall('/api/mihomo/routing/netrollback', {}, function (data) {
                                if (data['status'] === 'ok') {
                                    showMessage('{{ lang._('Rolled back') }}',
                                        (data['messages'] || []).join('\n'), BootstrapDialog.TYPE_SUCCESS);
                                } else {
                                    showMessage('{{ lang._('Apply failed') }}',
                                        data['message'] || '', BootstrapDialog.TYPE_DANGER);
                                }
                                loadNetState();
                                loadPolicyStatus();
                            });
                        }
                    }
                ]
            });
        });

        loadPolicyStatus();
        loadNetState();
    });
</script>

<div class="content-box __mb">
    <header class="content-box-header">
        <h3>{{ lang._('Policy Routing') }}</h3>
    </header>
    <p class="text-muted">
        {{ lang._('Bind a physical interface to mihomo: its traffic is policy routed into the TUN device, while interfaces without a row here are never routed into mihomo.') }}
        <span id="policyTunHint" class="text-warning hidden">
            {{ lang._('TUN is currently disabled, so these rules are stored but no traffic reaches mihomo yet.') }}
        </span>
    </p>
    <span id="policyStatusSummary" class="text-muted"></span>
</div>

<div class="content-box __mb">
    {{
        partial('layout_partials/base_bootgrid_table', formGridPolicy)
    }}
</div>

<div class="content-box __mb">
    <header class="content-box-header">
        <h3>{{ lang._('Effective state') }}</h3>
    </header>
    <table class="table table-condensed table-hover table-striped">
        <thead>
        <tr>
            <th style="width: 12%;">{{ lang._('Interface') }}</th>
            <th style="width: 18%;">{{ lang._('Source') }}</th>
            <th style="width: 22%;">{{ lang._('Outbound') }}</th>
            <th style="width: 20%;">{{ lang._('State') }}</th>
            <th>{{ lang._('Notes') }}</th>
        </tr>
        </thead>
        <tbody id="policyStatusBody"></tbody>
    </table>
</div>

<section class="grid-bottom-reserve __mt">
    <div class="alert content-box" style="display: flex; align-items: center; margin-bottom: 0;">
        <button class="btn btn-primary __mr" id="applyPolicyAct" type="button">{{ lang._('Apply') }}</button>
        <button class="btn btn-default __mr" id="previewPolicyAct" type="button">{{ lang._('Preview') }}</button>
        <button class="btn btn-default" id="refreshPolicyAct" type="button">{{ lang._('Refresh') }}</button>
    </div>
</section>

<div class="content-box __mb">
    <header class="content-box-header">
        <h3>{{ lang._('OPNsense side (interface, gateway, firewall)') }}</h3>
    </header>
    <p class="text-muted">
        {{ lang._('Traffic only reaches mihomo when the firewall policy routes the interface into the TUN device. Only interfaces whose policy routing is set to "Automatic" are touched; all other interfaces keep their normal routing.') }}
    </p>
    <table class="table table-condensed">
        <tbody id="netStateBody"></tbody>
    </table>
    <span id="netStateSummary" class="text-muted"></span>
</div>

<section class="grid-bottom-reserve __mt">
    <div class="alert content-box" style="display: flex; align-items: center; margin-bottom: 0;">
        <button class="btn btn-primary __mr" id="netApplyAct" type="button">{{ lang._('Synchronize OPNsense side') }}</button>
        <button class="btn btn-default __mr" id="netPlanAct" type="button">{{ lang._('Preview changes') }}</button>
        <button class="btn btn-default" id="netRollbackAct" type="button">{{ lang._('Roll back the OPNsense side') }}</button>
    </div>
</section>

{{ partial("layout_partials/base_dialog",['fields':formDialogPolicyRule,'id':formGridPolicy['edit_dialog_id'],'label':lang._('Edit Policy Rule')])}}
