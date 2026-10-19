{#
 # os-mihomo 二次开发 —— 设置
 #
 # 「设置」标签页 = OPNsense 原生 base_form 表单（写入 config.xml 的 mihomo 节点，
 # 再由 Apply 落到 config.yaml / rc.conf.d / env）；
 # 「配置文件」标签页 = 原始 YAML 编辑（经 configd + mihomo -t 校验后落盘）。
 #
 # Copyright (C) 2026  os-mihomo contributors
 # All rights reserved.
 # 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 #}

<script>
    $(document).ready(function () {
        function showResult(title, message, type) {
            BootstrapDialog.show({
                'type': type,
                'title': title,
                'message': $('<pre>').css({ 'white-space': 'pre-wrap', 'margin': '0', 'border': '0', 'background': 'transparent' }).text(message)
            });
        }

        /* ---------------------------------------------------------------- *
         * 「设置」标签页 —— 每一项标签旁的一把小锁
         *
         *   合上（淡，默认）= 不修改：插件完全不碰这一项，config.yaml 里原本怎么写就怎么用；
         *   打开（清楚）    = 由插件写入（点「应用」时按页面上的值覆盖文件）。
         *
         * 存储用反过来的写法：模型里的 mihomo.managed = **允许写入**的字段 id 列表（逗号分隔）。
         * ---------------------------------------------------------------- */
        const MANAGED_INPUT = 'mihomo.managed';
        /* 同一个 YAML 键由多个输入组成时共用一把锁 */
        const FIELD_GROUPS = [['mihomo.general.controllerBind', 'mihomo.general.controllerPort']];
        /* 没有小锁、始终由插件写的字段（后端 Config::fieldsWithoutSwitch()） */
        const ALWAYS_OWNED = ('{{ alwaysOwnedFields }}' || '').split(',').filter(Boolean);
        /* 写死的项：页面只读，值固定 */
        const FIXED = {};
        ('{{ fixedSettingPairs }}' || '').split(',').filter(Boolean).forEach(function (pair) {
            const bits = pair.split('=');
            if (bits.length === 2) {
                FIXED[bits[0]] = bits[1];
            }
        });

        function groupOf(id) {
            for (let i = 0; i < FIELD_GROUPS.length; i++) {
                if (FIELD_GROUPS[i].indexOf(id) >= 0) {
                    return FIELD_GROUPS[i];
                }
            }
            return null;
        }

        function fieldInputs() {
            const ids = [];
            $('#frm_Settings [id^="mihomo."]').each(function () {
                const id = $(this).attr('id');
                if (id && id !== MANAGED_INPUT && ids.indexOf(id) < 0) {
                    ids.push(id);
                }
            });
            return ids;
        }

        /* 一个字段（或它所在的组）是否交给插件写 */
        function groupOwned(id) {
            if (ALWAYS_OWNED.indexOf(id) >= 0) {
                return true;
            }
            const group = groupOf(id) || [id];
            return group.some(function (field) {
                return String($('[data-managed-for="' + field + '"]').attr('data-managed')) === '1';
            });
        }

        function managedFields() {
            return fieldInputs().filter(groupOwned);
        }

        function syncManagedHidden() {
            const owned = managedFields();
            const el = document.getElementById(MANAGED_INPUT);
            if (el) {
                el.value = owned.join(',');
            }
            return owned;
        }

        /* 小锁的两种样子：合上（灰）= 不修改；打开（蓝）= 由插件写 */
        function paintSwitch($sw) {
            const on = String($sw.attr('data-managed')) === '1';
            $sw.toggleClass('mihomo-on', on)
                .attr('title', on
                    ? '{{ lang._('Written by the plugin: on Apply the value above is written into the file. Click to leave the file alone instead.') }}'
                    : '{{ lang._('Leave alone: the plugin never writes this item, the file keeps whatever you wrote. Click to let the plugin write it here.') }}');
            $sw.find('i').toggleClass('fa-lock', !on).toggleClass('fa-unlock-alt', on);
        }

        /* 不写这一项的行：控件禁掉、灰掉；写死的项也禁掉（值固定） */
        function applyLeaveAlone() {
            fieldInputs().forEach(function (id) {
                const fixed = FIXED[id] !== undefined;
                const off = fixed || !groupOwned(id);
                const el = document.getElementById(id);
                if (!el) {
                    return;
                }
                const $el = $(el);
                if (fixed && String($el.val()) !== FIXED[id]) {
                    $el.val(FIXED[id]);
                }
                $el.prop('disabled', off);
                $el.closest('td').toggleClass('mihomo-leave-alone', off || fixed);
                if ($el.hasClass('selectpicker')) {
                    $el.selectpicker('refresh');
                }
            });
            $('[data-managed-for]').each(function () {
                paintSwitch($(this));
            });
        }

        /* 给每一行装上一把小锁（组内只在第一个输入上装一把）
           注意：字段 id 里带点（mihomo.tun.mtu），不能用 $('#xxx') 拼选择器 —— 点会被当成 class。
           一律走 getElementById。 */
        function buildManagedSwitches() {
            fieldInputs().forEach(function (id) {
                if (ALWAYS_OWNED.indexOf(id) >= 0) {
                    return;   // 插件自己的状态 / 写死的项：没有小锁
                }
                const group = groupOf(id);
                if (group && group[0] !== id) {
                    return;
                }
                const labelEl = document.getElementById('control_label_' + id);
                if (!labelEl) {
                    return;
                }
                const $label = $(labelEl);
                if ($label.find('[data-managed-for]').length) {
                    return;
                }
                const $sw = $('<a href="#">')
                    .addClass('mihomo-switch')
                    .attr('data-managed-for', id)
                    .attr('data-managed', '0')
                    .append($('<i>').addClass('fa fa-lock'));
                paintSwitch($sw);
                $label.append($sw);
            });
        }

        /* 写死的项（设备名/协议栈）：图钉一枚，鼠标移上去有说明 */
        function markFixedFields() {
            Object.keys(FIXED).forEach(function (id) {
                const labelEl = document.getElementById('control_label_' + id);
                if (!labelEl || $(labelEl).find('.mihomo-fixed-icon').length) {
                    return;
                }
                $('<i>')
                    .addClass('fa fa-thumb-tack mihomo-fixed-icon')
                    .attr('title', '{{ lang._('Fixed by the plugin and not editable here — see the help text.') }}')
                    .appendTo($(labelEl));
            });
        }

        /* 模型 → 小锁状态 */
        function applyManagedFromModel() {
            const hidden = document.getElementById(MANAGED_INPUT);
            const owned = String(hidden ? hidden.value : '').split(',');
            $('[data-managed-for]').each(function () {
                const id = String($(this).data('managed-for'));
                const group = groupOf(id) || [id];
                const isOwned = group.some(function (field) {
                    return owned.indexOf(field) >= 0;
                });
                $(this).attr('data-managed', isOwned ? '1' : '0');
            });
            applyLeaveAlone();
            syncManagedHidden();
        }

        function reloadForm() {
            return mapDataToFormUI({ 'frm_Settings': '/api/mihomo/settings/get' }).done(function () {
                formatTokenizersUI();
                $('.selectpicker').selectpicker('refresh');
                applyManagedFromModel();
            });
        }

        /* 开关状态通过这个隐藏字段随表单一起提交（模型里的 mihomo.managed） */
        $('<input type="hidden">').attr('id', MANAGED_INPUT).appendTo('#frm_Settings');

        buildManagedSwitches();
        markFixedFields();
        reloadForm();
        $(document).on('click', '.mihomo-switch', function (event) {
            event.preventDefault();
            const $sw = $(this);
            $sw.attr('data-managed', String($sw.attr('data-managed')) === '1' ? '0' : '1');
            applyLeaveAlone();
            syncManagedHidden();
        });

        $('#applyAct').click(function () {
            const $btn = $(this);
            $btn.prop('disabled', true);
            syncManagedHidden();
            saveFormToEndpoint('/api/mihomo/settings/set', 'frm_Settings', function () {
                ajaxCall('/api/mihomo/settings/apply', {
                    'restart': $('#restart-after-apply').prop('checked') ? 1 : 0
                }, function (data) {
                    $btn.prop('disabled', false);
                    if (data['status'] === 'ok') {
                        showResult('{{ lang._('Settings applied') }}', (data['messages'] || []).join('\n'), BootstrapDialog.TYPE_SUCCESS);
                        loadRawConfig();
                        reloadForm();
                    } else {
                        showResult('{{ lang._('Apply failed') }}', data['message'] || '', BootstrapDialog.TYPE_DANGER);
                    }
                });
            }, true, function () {
                $btn.prop('disabled', false);
            });
        });

        $('#importAct').click(function () {
            ajaxCall('/api/mihomo/settings/import', {}, function (data) {
                if (data['status'] === 'ok') {
                    reloadForm();
                    showResult('{{ lang._('Settings imported') }}', (data['messages'] || []).join('\n'), BootstrapDialog.TYPE_INFO);
                } else {
                    showResult('{{ lang._('Import failed') }}', data['message'] || '', BootstrapDialog.TYPE_DANGER);
                }
            });
        });

        /* ---------------------------------------------------------------- *
         * 「配置文件」标签页
         * ---------------------------------------------------------------- */
        /* ------------------------------------------------------------------ *
         * 配置对照：页面值 / 文件值 / 运行值（只读）
         * ------------------------------------------------------------------ */
        function escapeHtml(text) {
            return $('<div>').text(text === undefined || text === null ? '' : String(text)).html();
        }

        function renderCompare(data) {
            const $body = $('#compare-body').empty();

            (data['rows'] || []).forEach(function (row) {
                let badge;
                if (row['runtime_only']) {
                    badge = '<span class="label label-default">{{ lang._('running only') }}</span>';
                } else if (row['state'] === 'differs') {
                    badge = '<span class="label label-warning">{{ lang._('different') }}</span>';
                } else if (row['state'] === 'missing') {
                    badge = '<span class="label label-default">{{ lang._('not in file') }}</span>';
                } else {
                    badge = '<span class="label label-success">{{ lang._('consistent') }}</span>';
                }
                $('<tr>')
                    .append($('<td>').html('<b>' + escapeHtml(row['label']) + '</b> ' + badge))
                    .append($('<td>').html(escapeHtml(row['model'] || '—')
                        + (row['managed'] === false
                            ? ' <span class="label label-default">{{ lang._('leave alone') }}</span>'
                            : '')))
                    .append($('<td>').text(row['file'] || '—'))
                    .append($('<td>').text(row['runtime'] || '—'))
                    .appendTo($body);
            });
        }

        function loadCompare() {
            ajaxGet('/api/mihomo/settings/inspect', {}, renderCompare);
        }

        $('#compare-refresh').click(loadCompare);
        $('#compareTab').on('shown.bs.tab', loadCompare);

        /* ------------------------------------------------------------------ *
         * 原始配置编辑器
         * ------------------------------------------------------------------ */
        function loadRawConfig() {
            ajaxGet('/api/mihomo/settings/config_get', {}, function (data) {
                if (data['status'] === 'ok') {
                    $('#config-editor').val(data['content']);
                    $('#config-info').text(data['file'] + '  ·  ' + data['bytes'] + ' ' + '{{ lang._('bytes') }}');
                } else {
                    $('#config-editor').val('');
                    $('#config-info').text('{{ lang._('Configuration file not found.') }}');
                }
            });
        }

        $('#config-validate').click(function () {
            ajaxCall('/api/mihomo/settings/config_validate', { 'content': $('#config-editor').val() }, function (data) {
                showResult(
                    data['status'] === 'ok' ? '{{ lang._('Validation passed') }}' : '{{ lang._('Validation failed') }}',
                    data['message'] || '',
                    data['status'] === 'ok' ? BootstrapDialog.TYPE_SUCCESS : BootstrapDialog.TYPE_DANGER
                );
            });
        });

        $('#config-save').click(function () {
            ajaxCall('/api/mihomo/settings/config_set', { 'content': $('#config-editor').val() }, function (data) {
                showResult(
                    data['status'] === 'ok' ? '{{ lang._('Configuration saved') }}' : '{{ lang._('Save failed') }}',
                    data['message'] || '',
                    data['status'] === 'ok' ? BootstrapDialog.TYPE_SUCCESS : BootstrapDialog.TYPE_DANGER
                );
                if (data['status'] === 'ok') {
                    loadRawConfig();
                }
            });
        });

        $('#config-test').click(function () {
            ajaxCall('/api/mihomo/settings/config_test', {}, function (data) {
                showResult(
                    data['status'] === 'ok' ? '{{ lang._('Active configuration is valid') }}' : '{{ lang._('Active configuration is invalid') }}',
                    data['message'] || '',
                    data['status'] === 'ok' ? BootstrapDialog.TYPE_SUCCESS : BootstrapDialog.TYPE_DANGER
                );
            });
        });

        loadRawConfig();
    });
</script>

<style>
    /* 每一行标签旁的一把小锁：合上（淡）= 不修改，打开（清楚）= 由插件写。
       颜色继承主题正文色，只用浓淡区分，浅色/深色主题都合身。 */
    .mihomo-switch {
        margin-left: 7px;
        padding: 1px 4px;
        border-radius: 3px;
        color: inherit;
        opacity: .45;
        text-decoration: none !important;
    }
    .mihomo-switch.mihomo-on {
        opacity: 1;
    }
    .mihomo-switch:hover,
    .mihomo-switch:focus {
        opacity: 1;
        background-color: rgba(128, 128, 128, .22);
    }
    /* 写死的项（设备名 / 协议栈）：图钉一枚，不可点 */
    .mihomo-fixed-icon {
        margin-left: 7px;
        opacity: .6;
        cursor: default;
    }
</style>

<ul class="nav nav-tabs" role="tablist" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#settings">{{ lang._('Settings') }}</a></li>
    <li><a data-toggle="tab" href="#config">{{ lang._('Configuration File') }}</a></li>
    <li><a data-toggle="tab" href="#compare" id="compareTab">{{ lang._('Configuration comparison') }}</a></li>
</ul>
<div class="tab-content content-box">
    <div id="settings" class="tab-pane fade in active">
        {{ partial("layout_partials/base_form",['fields':formSettings,'id':'frm_Settings'])}}
    </div>
    <div id="config" class="tab-pane fade in">
        <div style="padding: 12px 14px;">
            <div class="alert alert-info" style="margin-bottom: 10px;">
                <i class="fa fa-info-circle fa-fw"></i>
                {{ lang._('Validated with mihomo -t before it replaces the active file; the previous file is kept as a backup.') }}
                <span class="pull-right" id="config-info"></span>
            </div>
            <textarea id="config-editor" class="form-control" rows="26" spellcheck="false"
                      style="width: 100%; max-width: 100%; font-family: Menlo, Monaco, Consolas, 'Courier New', monospace; font-size: 13px; white-space: pre; overflow-wrap: normal; resize: vertical;"></textarea>
            <div style="margin-top: 10px;">
                <button type="button" class="btn btn-default" id="config-test"><i class="fa fa-check-circle fa-fw"></i> {{ lang._('Test Active Configuration') }}</button>
                <button type="button" class="btn btn-default" id="config-validate"><i class="fa fa-flask fa-fw"></i> {{ lang._('Validate') }}</button>
                <button type="button" class="btn btn-primary" id="config-save"><i class="fa fa-save fa-fw"></i> {{ lang._('Save') }}</button>
            </div>
        </div>
    </div>
    <div id="compare" class="tab-pane fade in">
        <div style="padding: 12px 14px;">
            <table class="table table-condensed table-hover" id="compare-table">
                <thead>
                <tr>
                    <th style="width: 22%;">{{ lang._('Item') }}</th>
                    <th style="width: 26%;">{{ lang._('WebGUI') }}</th>
                    <th style="width: 26%;">{{ lang._('File (config.yaml)') }}</th>
                    <th style="width: 26%;">{{ lang._('Running (memory)') }}</th>
                </tr>
                </thead>
                <tbody id="compare-body"></tbody>
            </table>
            <div class="text-right">
                <button class="btn btn-default btn-sm" id="compare-refresh" type="button">
                    <i class="fa fa-refresh fa-fw"></i> {{ lang._('Refresh') }}
                </button>
            </div>
        </div>
    </div>
</div>

<section class="grid-bottom-reserve __mt">
    <div class="alert content-box" style="margin-bottom: 0;">
        <div class="clearfix">
            <div class="pull-left">
                <button class="btn btn-primary __mr" id="applyAct" type="button"><b>{{ lang._('Apply') }}</b></button>
                <button class="btn btn-default __mr" id="importAct" type="button"><i class="fa fa-download fa-fw"></i> {{ lang._('Import from configuration file') }}</button>
                <label style="font-weight: normal; margin: 0 10px 0 4px;">
                    <input type="checkbox" id="restart-after-apply"> {{ lang._('Restart the service after applying') }}
                </label>
            </div>
        </div>
    </div>
</section>
