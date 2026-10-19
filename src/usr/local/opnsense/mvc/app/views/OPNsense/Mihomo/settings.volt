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
         * 「设置」标签页 —— 每一项前面的「不修改」开关
         *
         *   勾上（默认）= 不修改：插件完全不碰这一项，config.yaml 里原本怎么写就怎么用；
         *   取消勾       = 由插件写入（覆盖）。
         *
         * 存储用反过来的写法：模型里的 mihomo.managed = **允许写入**的字段 id 列表（逗号分隔）。
         * ---------------------------------------------------------------- */
        const MANAGED_INPUT = 'mihomo.managed';
        /* 同一个 YAML 键由多个输入组成时共用一个开关 */
        const FIELD_GROUPS = [['mihomo.general.controllerBind', 'mihomo.general.controllerPort']];

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

        /* 字段的中文名：优先取表单标签，取不到就用字段 id */
        function fieldLabel(id) {
            let text = '';
            const ctl = document.getElementById('control_label_' + id);
            if (ctl) {
                /* 标签单元格里有我们自己塞的「不修改」开关，取名字时先摘掉它 */
                const $clone = $(ctl).clone();
                $clone.find('label.mihomo-managed-switch').remove();
                text = $clone.text();
            }
            if (!text) {
                const $label = $('label[for="' + id + '"]');
                if ($label.length) {
                    text = $label.first().clone().children().remove().end().text();
                }
            }
            text = String(text || '').replace(/\s+/g, ' ').trim();
            return text || id;
        }

        /* 一个字段（或它所在的组）是否交给插件写 */
        function groupOwned(id) {
            const group = groupOf(id) || [id];
            let owned = false;
            group.forEach(function (field) {
                const $box = $('[data-managed-for="' + field + '"]');
                if ($box.length && !$box.prop('checked')) {
                    owned = true;
                }
            });
            return owned;
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

        /* 勾上「不修改」的行：控件禁掉、灰掉，看一眼就知道插件不会动它 */
        function applyLeaveAlone() {
            fieldInputs().forEach(function (id) {
                const off = !groupOwned(id);
                const el = document.getElementById(id);
                if (!el) {
                    return;
                }
                const $el = $(el);
                $el.prop('disabled', off);
                $el.closest('td').toggleClass('mihomo-leave-alone', off);
                if ($el.hasClass('selectpicker')) {
                    $el.selectpicker('refresh');
                }
            });
        }

        function refreshManagedSummary() {
            const owned = syncManagedHidden();
            $('#changed-summary').text(owned.length === 0
                ? '{{ lang._('Every item is set to "leave alone" — pressing Apply will not touch the configuration file.') }}'
                : '{{ lang._('Will be written') }}: ' + owned.map(fieldLabel).join('、'));
        }

        /* 给每一行装上开关（组内只在第一个输入上装一条）
           注意：字段 id 里带点（mihomo.tun.mtu），不能用 $('#xxx') 拼选择器 —— 点会被当成 class。
           一律走 getElementById。 */
        function buildManagedSwitches() {
            fieldInputs().forEach(function (id) {
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
                $('<label>')
                    .addClass('mihomo-managed-switch')
                    .attr('title', '{{ lang._('Tick = this plugin never writes this item: the file keeps whatever you wrote. Clear the tick to let the page write it.') }}')
                    .append($('<input type="checkbox" checked>').attr('data-managed-for', id))
                    .append($('<span>').text('{{ lang._('leave alone') }}'))
                    .prependTo($label);
            });
        }

        /* 模型 → 开关状态 */
        function applyManagedFromModel() {
            const hidden = document.getElementById(MANAGED_INPUT);
            const owned = String(hidden ? hidden.value : '').split(',');
            $('[data-managed-for]').each(function () {
                const id = String($(this).data('managed-for'));
                const group = groupOf(id) || [id];
                const isOwned = group.some(function (field) {
                    return owned.indexOf(field) >= 0;
                });
                $(this).prop('checked', !isOwned);
            });
            applyLeaveAlone();
            refreshManagedSummary();
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
        reloadForm();
        $(document).on('change', '[data-managed-for]', function () {
            applyLeaveAlone();
            refreshManagedSummary();
        });
        $('[id^="mihomo."]').on('change input', refreshManagedSummary);
        $('#managedAllAct').click(function () {
            $('[data-managed-for]').prop('checked', false);
            applyLeaveAlone();
            refreshManagedSummary();
        });
        $('#managedNoneAct').click(function () {
            $('[data-managed-for]').prop('checked', true);
            applyLeaveAlone();
            refreshManagedSummary();
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
            const $notes = $('#compare-notes').empty();
            const $body = $('#compare-body').empty();

            (data['notes'] || []).forEach(function (note) {
                const warn = note['level'] === 'warning';
                $('<div>')
                    .addClass('alert ' + (warn ? 'alert-warning' : 'alert-info'))
                    .css({ 'margin-bottom': '8px' })
                    .html('<i class="fa ' + (warn ? 'fa-exclamation-triangle' : 'fa-info-circle') + ' fa-fw"></i> '
                        + escapeHtml(note['text']))
                    .appendTo($notes);
            });

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
    /* 「不修改」开关：贴在每一项的标签前面 */
    .mihomo-managed-switch {
        font-weight: normal;
        font-size: 11px;
        color: #777;
        margin: 0 8px 0 0;
        padding: 0 4px;
        white-space: nowrap;
        cursor: pointer;
    }
    .mihomo-managed-switch input {
        margin: 0 3px 0 0;
        vertical-align: -1px;
    }
    /* 勾了「不修改」的行：控件禁掉并变灰 */
    .mihomo-leave-alone input,
    .mihomo-leave-alone select,
    .mihomo-leave-alone textarea {
        background-color: #f5f5f5;
        color: #999;
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
            <p class="text-muted" style="margin-bottom: 10px;">
                {{ lang._('The same setting can live in three places. This table shows all three: what the WebGUI remembers, what the file says, and what the running core actually uses.') }}
                {{ lang._('Rows marked with a "leave alone" tag are items this plugin does not write: whatever you put in the file stays as it is.') }}
            </p>
            <div id="compare-notes"></div>
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
        <div style="margin-top: 10px;">
            <span class="text-muted" style="font-size: 12px;">
                {{ lang._('Each item has a "leave alone" tick (on by default): this plugin then never writes that item — the file keeps whatever you wrote, and what is not in the file stays out. Clear the tick to let the page write it.') }}
            </span>
        </div>
        <div style="margin-top: 6px;">
            <button class="btn btn-xs btn-default __mr" id="managedAllAct" type="button"
                    title="{{ lang._('Let the page write every item.') }}">{{ lang._('Tick nothing (write all)') }}</button>
            <button class="btn btn-xs btn-default" id="managedNoneAct" type="button"
                    title="{{ lang._('Nothing is written to any file.') }}">{{ lang._('Tick everything (leave all alone)') }}</button>
        </div>
        <div id="changed-summary" class="text-muted" style="margin-top: 8px; font-size: 12px;"></div>
    </div>
</section>
