{#
 # os-mihomo 二次开发 —— 订阅
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

        function loadSettings() {
            ajaxGet('/api/mihomo/subscription/get', {}, function (data) {
                $('[id="mihomo.subscription.url"]').val(data['url'] || '');
                $('[id="mihomo.subscription.secret"]').val(data['secret'] || '');
                $('#env-file').text(data['envFile'] || '');
                if (!data['scriptAvailable']) {
                    $('#sub-unavailable').show();
                }
            });
        }

        function refreshLogs(scroll) {
            ajaxGet('/api/mihomo/subscription/log', { 'lines': 400 }, function (data) {
                const $viewer = $('#log-viewer');
                const atBottom = $viewer.length > 0 && ($viewer[0].scrollHeight - $viewer.scrollTop() - $viewer.outerHeight()) < 40;
                $viewer.val(data['content'] || '');
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
                        data['status'] === 'ok' ? '{{ lang._('Settings saved') }}' : '{{ lang._('Save failed') }}',
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
                        data['status'] === 'ok' ? '{{ lang._('Subscription update started') }}' : '{{ lang._('Subscription update failed') }}',
                        data['message'] || '',
                        data['status'] === 'ok' ? BootstrapDialog.TYPE_INFO : BootstrapDialog.TYPE_DANGER
                    );
                    setTimeout(function () { refreshLogs(true); }, 1500);
                });
            };

            if (restart) {
                BootstrapDialog.confirm({
                    'type': BootstrapDialog.TYPE_WARNING,
                    'title': '{{ lang._('Restart service?') }}',
                    'message': '{{ lang._('The service will be restarted right after the update, which rebuilds the TUN device and its routes. Make sure the new nodes work, otherwise clients behind this firewall may lose connectivity.') }}',
                    'callback': function (result) { if (result) { confirmRestart(); } }
                });
            } else {
                confirmRestart();
            }
        });

        $('#clearLogAct').click(function () {
            ajaxCall('/api/mihomo/subscription/clear_log', {}, function (data) {
                showResult('{{ lang._('Log') }}', data['message'] || '', BootstrapDialog.TYPE_INFO);
                refreshLogs(true);
            });
        });

        $('#refreshLogAct').click(function () { refreshLogs(true); });

        loadSettings();
        refreshLogs(true);
        setInterval(function () { refreshLogs(false); }, 5000);
    });
</script>

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
            <div style="padding: 12px 14px; border-bottom: 1px solid #eeeeee;">
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
                        <input type="text" id="mihomo.subscription.secret" class="form-control" size="30" autocomplete="off"
                               placeholder="{{ lang._('Enter dashboard access secret') }}">
                    </div>
                    <div style="margin-top: 12px;">
                        <button type="button" class="btn btn-primary" id="saveAct"><i class="fa fa-save fa-fw"></i> {{ lang._('Save Settings') }}</button>
                        <button type="button" class="btn btn-success" id="runAct"><i class="fa fa-refresh fa-fw"></i> {{ lang._('Start Subscription') }}</button>
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
            <div style="padding: 12px 14px; border-bottom: 1px solid #eeeeee;">
                <i class="fa fa-file-text text-muted"></i> <b>{{ lang._('Log Viewer') }}</b>
                <span class="pull-right">
                    <button type="button" class="btn btn-xs btn-default" id="refreshLogAct"><i class="fa fa-refresh fa-fw"></i></button>
                    <button type="button" class="btn btn-xs btn-default" id="clearLogAct"><i class="fa fa-trash fa-fw"></i> {{ lang._('Clear Log') }}</button>
                </span>
            </div>
            <div style="padding: 14px;">
                <textarea id="log-viewer" class="form-control" rows="18" readonly
                          style="width: 100%; max-width: 100%; font-family: Menlo, Monaco, Consolas, 'Courier New', monospace; font-size: 13px; white-space: pre-wrap; overflow-wrap: anywhere;"></textarea>
            </div>
        </div>
    </section>
</div>
