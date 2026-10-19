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
         * 「设置」标签页
         *
         * 「只写入我改过的项」：页面装载时记一份快照，提交时只把动过的字段名列给后端，
         * 后端据此只改 config.yaml 里对应的那几行 —— 文件里没动过的值不会被顺手覆盖。
         * ---------------------------------------------------------------- */
        let formSnapshot = {};

        function fieldValue($el) {
            return $el.is(':checkbox') ? ($el.prop('checked') ? '1' : '0') : String($el.val() === null ? '' : $el.val());
        }

        function collectForm() {
            const values = {};
            $('[id^="mihomo."]').each(function () {
                const id = $(this).attr('id');
                if (id && !Object.prototype.hasOwnProperty.call(values, id)) {
                    values[id] = fieldValue($(this));
                }
            });
            return values;
        }

        /* 字段的中文名：优先取表单标签，取不到就用字段 id */
        function fieldLabel(id) {
            let text = '';
            const $label = $('label[for="' + id + '"]');
            if ($label.length) {
                text = $label.first().clone().children().remove().end().text();
            }
            if (!text) {
                const $ctl = document.getElementById('control_label_' + id);
                if ($ctl) {
                    text = $($ctl).clone().children().remove().end().text();
                }
            }
            text = String(text || '').replace(/\s+/g, ' ').trim();
            return text || id;
        }

        function changedFields() {
            const now = collectForm();
            const changed = [];
            Object.keys(now).forEach(function (id) {
                if (formSnapshot[id] !== undefined && formSnapshot[id] !== now[id]) {
                    changed.push(id);
                }
            });
            return changed;
        }

        function refreshChangedSummary() {
            const mode = $('input[name=applymode]:checked').val();
            const changed = changedFields();
            let text;
            if (mode === 'all') {
                text = '{{ lang._('All page settings will be written into the file.') }}';
            } else if (changed.length === 0) {
                text = '{{ lang._('You have not changed anything yet — pressing Apply will not write to the file.') }}';
            } else {
                text = '{{ lang._('Will be written') }}: ' + changed.map(fieldLabel).join('、');
            }
            $('#changed-summary').text(text);
        }

        function takeSnapshot() {
            formSnapshot = collectForm();
            refreshChangedSummary();
        }

        function reloadForm() {
            return mapDataToFormUI({ 'frm_Settings': '/api/mihomo/settings/get' }).done(function () {
                formatTokenizersUI();
                $('.selectpicker').selectpicker('refresh');
                takeSnapshot();
            });
        }

        reloadForm();
        $(document).on('change input', '[id^="mihomo."]', refreshChangedSummary);
        $('input[name=applymode]').on('change', refreshChangedSummary);

        $('#applyAct').click(function () {
            const $btn = $(this);
            $btn.prop('disabled', true);
            const changed = changedFields();
            saveFormToEndpoint('/api/mihomo/settings/set', 'frm_Settings', function () {
                ajaxCall('/api/mihomo/settings/apply', {
                    'restart': $('#restart-after-apply').prop('checked') ? 1 : 0,
                    'mode': $('input[name=applymode]:checked').val(),
                    'changed': JSON.stringify(changed)
                }, function (data) {
                    $btn.prop('disabled', false);
                    if (data['status'] === 'ok') {
                        showResult('{{ lang._('Settings applied') }}', (data['messages'] || []).join('\n'), BootstrapDialog.TYPE_SUCCESS);
                        loadRawConfig();
                        takeSnapshot();
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
                    .append($('<td>').text(row['model'] || '—'))
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
            <label class="radio-inline">
                <input type="radio" name="applymode" value="changed" checked>
                {{ lang._('Write only what I changed (recommended)') }}
            </label>
            <label class="radio-inline" style="margin-left: 14px;">
                <input type="radio" name="applymode" value="all">
                {{ lang._('Write all page settings into the file') }}
            </label>
        </div>
        <div id="changed-summary" class="text-muted" style="margin-top: 8px; font-size: 12px;"></div>
    </div>
</section>
