{#
 # os-mihomo 二次开发 —— 订阅
 #
 # Copyright (C) 2026  os-mihomo contributors
 # All rights reserved.
 # 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 #}
{% set lang = mihomoLang %}
<script src="{{ cache_safe('/js/mihomo/ui.js') }}"></script>


<script>
    $(document).ready(function () {
        function showResult(title, message, type) {
            BootstrapDialog.show({
                'type': type,
                'title': title,
                'message': $('<pre>').css({ 'white-space': 'pre-wrap', 'margin': '0', 'border': '0', 'background': 'transparent' }).text(message)
            });
        }

        let savedUrl = '', savedSecret = '', taskRunning = false, taskKnown = false;
        function updateSubmitState() {
            const changed = $('[id="mihomo.subscription.url"]').val() !== savedUrl || $('[id="mihomo.subscription.secret"]').val() !== savedSecret;
            $('#saveAct').prop('disabled', !changed);
            $('#runAct').prop('disabled', !taskKnown || taskRunning || changed || !savedUrl);
            $('#subscription-edit-state').text(changed ? {{ lang._('Save subscription settings before submitting an update.') | json_encode }}
                : !savedUrl ? {{ lang._('Set a subscription URL in Settings to enable updates.') | json_encode }} : '');
        }
        function refreshTask() {
            ajaxGet('/api/mihomo/dashboard/runtime_status', {}, function (data, status) {
                if (status !== 'success' || !data || data.status !== 'ok') { taskKnown = false; updateSubmitState(); $('#subscription-task-state').text({{ lang._('Status unavailable') | json_encode }}); return; }
                taskKnown = true;
                const task = data.subscription || {};
                const states = {running: {{ lang._('Updating') | json_encode }}, success: {{ lang._('Last update succeeded') | json_encode }},
                    failed: {{ lang._('Last update failed') | json_encode }}, incomplete: {{ lang._('Completion not recorded') | json_encode }},
                    idle: {{ lang._('No task recorded') | json_encode }}, unknown: {{ lang._('No structured task record') | json_encode }}};
                taskRunning = task.state === 'running';
                $('#subscription-task-state').text(states[task.state] || {{ lang._('Status unavailable') | json_encode }});
                $('#subscription-last-success').text(task.last_success || '—');
                $('#subscription-last-finish').text(task.finished || '—');
                $('#subscription-exit').text(task.exit_code === null || task.exit_code === undefined ? '—' : task.exit_code);
                updateSubmitState();
            });
        }
        $('[id="mihomo.subscription.url"], [id="mihomo.subscription.secret"]').on('input change', updateSubmitState);

        function loadSettings() {
            ajaxGet('/api/mihomo/subscription/get', {}, function (data) {
                $('[id="mihomo.subscription.url"]').val(MihomoUI.decodeApiText(data['url']));
                $('[id="mihomo.subscription.secret"]').val(MihomoUI.decodeApiText(data['secret']));
                savedUrl = MihomoUI.decodeApiText(data['url']);
                savedSecret = MihomoUI.decodeApiText(data['secret']);
                updateSubmitState();
                $('#env-file').text(data['envFile'] || '');
                if (!data['scriptAvailable']) {
                    $('#sub-unavailable').show();
                }
            });
        }

        function refreshLogs(scroll) {
            ajaxGet('/api/mihomo/subscription/log', { 'lines': 400 }, function (data, status) {
                if (status !== 'success' || !data || data.status !== 'ok') {
                    $('#log-state').text({{ lang._('Could not read the log. Try refreshing.') | json_encode }}); return;
                }
                const content = MihomoUI.decodeApiText(data.content);
                $('#log-state').text(content ? {{ lang._('Log updated') | json_encode }} : {{ lang._('No log entries yet.') | json_encode }});
                const $viewer = $('#log-viewer');
                const atBottom = $viewer.length > 0 && ($viewer[0].scrollHeight - $viewer.scrollTop() - $viewer.outerHeight()) < 40;
                $viewer.val(content);
                if (scroll || atBottom) {
                    $viewer.scrollTop($viewer[0].scrollHeight);
                }
            });
        }

        $('#saveAct').click(function () {
            const $btn = $(this);
            $btn.prop('disabled', true);
            saveFormToEndpoint('/api/mihomo/settings/set', 'frm_Subscription', function () {
                ajaxCall('/api/mihomo/subscription/save', {
                    'url': $('[id="mihomo.subscription.url"]').val(),
                    'secret': $('[id="mihomo.subscription.secret"]').val()
                }, function (data) {
                    $btn.prop('disabled', false);
                    showResult(
                        data['status'] === 'ok' ? ({{ lang._('Settings saved') | json_encode }}) : ({{ lang._('Save failed') | json_encode }}),
                        data['message'] || '',
                        data['status'] === 'ok' ? BootstrapDialog.TYPE_SUCCESS : BootstrapDialog.TYPE_DANGER
                    );
                    loadSettings();
                });
            }, true, function () {
                $btn.prop('disabled', false);
            });
        });

        $('#runAct').click(function () {
            const $btn = $(this);
            const restart = $('#restart-after-update').prop('checked');
            const confirmRestart = function () {
                $btn.prop('disabled', true);
                ajaxCall('/api/mihomo/subscription/run', { 'restart': restart ? 1 : 0 }, function (data) {
                    $btn.prop('disabled', false);
                    showResult(
                        data['status'] === 'ok' ? ({{ lang._('Subscription update started') | json_encode }}) : ({{ lang._('Subscription update failed') | json_encode }}),
                        data['message'] || '',
                        data['status'] === 'ok' ? BootstrapDialog.TYPE_INFO : BootstrapDialog.TYPE_DANGER
                    );
                    refreshTask();
                    setTimeout(function () { refreshLogs(true); refreshTask(); }, 1500);
                });
            };

            if (restart) {
                BootstrapDialog.confirm({
                    'type': BootstrapDialog.TYPE_WARNING,
                    'title': ({{ lang._('Restart service?') | json_encode }}),
                    'message': ({{ lang._('The service will be restarted right after the update, which rebuilds the TUN device and its routes. Make sure the new nodes work, otherwise clients behind this firewall may lose connectivity.') | json_encode }}),
                    'callback': function (result) { if (result) { confirmRestart(); } }
                });
            } else {
                confirmRestart();
            }
        });

        $('#clearLogAct').click(function () {
            ajaxCall('/api/mihomo/subscription/clear_log', {}, function (data) {
                showResult(({{ lang._('Log') | json_encode }}), data['message'] || '', BootstrapDialog.TYPE_INFO);
                refreshLogs(true);
            });
        });

        $('#refreshLogAct').click(function () { refreshLogs(true); });

        loadSettings();
        refreshTask();
        refreshLogs(true);
        setInterval(function () { if (!document.hidden) { refreshLogs(false); refreshTask(); } }, 5000);
    });
</script>

<div class="row"><section class="col-xs-12"><div class="content-box" style="padding:14px; margin-bottom:15px;">
    <h4>{{ lang._('Subscription task') }}</h4>
    <dl class="dl-horizontal" style="margin-bottom:10px;">
        <dt>{{ lang._('Status') }}</dt><dd id="subscription-task-state" role="status">{{ lang._('Loading …') }}</dd>
        <dt>{{ lang._('Last successful update') }}</dt><dd id="subscription-last-success">—</dd>
        <dt>{{ lang._('Last completion') }}</dt><dd id="subscription-last-finish">—</dd>
        <dt>{{ lang._('Exit code') }}</dt><dd id="subscription-exit">—</dd>
    </dl>
    <p class="text-muted">{{ lang._('Times use the device time zone. Results come from the retained task log; older records may have been rotated.') }}</p>
</div></section></div>
<div class="row">
    <section class="col-xs-12">
        <div id="sub-unavailable" class="alert alert-warning" style="display: none;">
            <i class="fa fa-exclamation-triangle fa-fw"></i>
            {{ lang._('The subscription script is not installed; subscription updates are unavailable.') }}
        </div>
    </section>
</div>

<div class="row">
    <section class="col-xs-12">
        <div class="alert alert-warning">
            <i class="fa fa-exclamation-triangle fa-fw"></i>
            {{ lang._('Updating the subscription rebuilds config.yaml from the subscription template, so manual edits are replaced. The current file is backed up as config.yaml.bak.sub_* first.') }}
        </div>
    </section>
</div>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding: 12px 14px; ">
                <i class="fa fa-link text-muted"></i> <b>{{ lang._('Subscription Management') }}</b>
                <span class="pull-right text-muted" style="font-size: 11px;" id="env-file"></span>
            </div>
            <div style="padding: 14px;">
                <form id="frm_Subscription" class="form-inline">
                    <div class="form-group">
                        <label class="control-label" for="mihomo.subscription.url">{{ lang._('Subscription URL') }}</label>
                        <input type="text" id="mihomo.subscription.url" class="form-control" size="60" autocomplete="off"
                               placeholder="{{ lang._('Enter HTTP or HTTPS subscription URL') }}">
                    </div>
                    <div class="form-group" style="margin-left: 15px;">
                        <label class="control-label" for="mihomo.subscription.secret">{{ lang._('Access Secret') }}</label>
                        <input type="password" id="mihomo.subscription.secret" class="form-control" size="30" autocomplete="off"
                               placeholder="{{ lang._('Enter dashboard access secret') }}">
                    </div>
                    <p id="subscription-edit-state" class="text-muted" role="status" style="margin-top:10px;"></p>
                    <div style="margin-top: 12px;">
                        <button type="button" class="btn btn-primary" id="saveAct" disabled><i class="fa fa-save fa-fw"></i> {{ lang._('Save Settings') }}</button>
                        <button type="button" class="btn btn-success" id="runAct" disabled><i class="fa fa-refresh fa-fw"></i> {{ lang._('Update subscription') }}</button>
                        <label style="font-weight: normal; margin-left: 12px;">
                            <input type="checkbox" id="restart-after-update"> {{ lang._('Restart service after a successful update') }}
                        </label>
                    </div>
                </form>
            </div>
        </div>
    </section>
</div>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding: 12px 14px; ">
                <i class="fa fa-file-text text-muted"></i> <b>{{ lang._('Log Viewer') }}</b>
                <span class="pull-right">
                    <button type="button" class="btn btn-xs btn-default" id="refreshLogAct" title="{{ lang._('Refresh') }}" aria-label="{{ lang._('Refresh') }}"><i class="fa fa-refresh fa-fw"></i></button>
                    <button type="button" class="btn btn-xs btn-default" id="clearLogAct" title="{{ lang._('Clear Log') }}" aria-label="{{ lang._('Clear Log') }}"><i class="fa fa-trash fa-fw"></i> {{ lang._('Clear Log') }}</button>
                </span>
            </div>
            <div style="padding: 14px;">
                <p id="log-state" class="text-muted" role="status"></p>
                <textarea aria-label="{{ lang._('Log contents') }}" id="log-viewer" class="form-control" rows="18" readonly
                          style="width: 100%; max-width: 100%; font-family: Menlo, Monaco, Consolas, 'Courier New', monospace; font-size: 13px; white-space: pre-wrap; overflow-wrap: anywhere;"></textarea>
            </div>
        </div>
    </section>
</div>
