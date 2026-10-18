{#
 # os-mihomo 二次开发 —— 日志
 #
 # 日志文件由 root 拥有，读取统一走 configd，因此不需要放宽任何文件权限。
 #
 # Copyright (C) 2026  os-mihomo contributors
 # All rights reserved.
 # 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 #}

<script>
    $(document).ready(function () {
        function refreshLogs(scroll) {
            const key = $('#log-source').val();
            ajaxGet('/api/mihomo/log/tail', { 'key': key, 'lines': $('#log-lines').val() }, function (data) {
                const $viewer = $('#log-viewer');
                const atBottom = $viewer[0].scrollHeight - $viewer.scrollTop() - $viewer.outerHeight() < 40;
                $viewer.val(data['content'] || '');
                if (scroll || atBottom) {
                    $viewer.scrollTop($viewer[0].scrollHeight);
                }
            });
        }

        $('#log-source').change(function () { refreshLogs(true); });
        $('#log-lines').change(function () { refreshLogs(true); });
        $('#refreshAct').click(function () { refreshLogs(true); });
        $('#downloadAct').click(function () {
            const key = $('#log-source').val();
            ajaxGet('/api/mihomo/log/tail', { 'key': key, 'lines': 5000 }, function (data) {
                const blob = new Blob([data['content'] || ''], { 'type': 'text/plain' });
                const link = document.createElement('a');
                link.href = URL.createObjectURL(blob);
                link.download = key + '.log';
                link.click();
                URL.revokeObjectURL(link.href);
            });
        });
        $('#clearAct').click(function () {
            BootstrapDialog.confirm({
                'type': BootstrapDialog.TYPE_WARNING,
                'title': '{{ lang._('Clear log?') }}',
                'message': '{{ lang._('The selected log file will be emptied.') }}',
                'callback': function (result) {
                    if (!result) {
                        return;
                    }
                    ajaxCall('/api/mihomo/log/clear', { 'key': $('#log-source').val() }, function () {
                        refreshLogs(true);
                    });
                }
            });
        });

        refreshLogs(true);
        setInterval(function () { refreshLogs(false); }, 5000);
    });
</script>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding: 12px 14px; border-bottom: 1px solid #eeeeee;">
                <i class="fa fa-file-text-o text-muted"></i> <b>{{ lang._('Log File') }}</b>
                <span class="pull-right">
                    <select id="log-source" class="form-control" style="width: auto; display: inline-block; height: 28px; padding: 2px 6px;">
                        <option value="mihomo">{{ lang._('Core log') }} — /var/log/mihomo.log</option>
                        <option value="subscription">{{ lang._('Subscription log') }} — /var/log/mihomo_sub.log</option>
                    </select>
                    <select id="log-lines" class="form-control" style="width: auto; display: inline-block; height: 28px; padding: 2px 6px;">
                        <option value="100">100</option>
                        <option value="300" selected="selected">300</option>
                        <option value="1000">1000</option>
                        <option value="3000">3000</option>
                    </select>
                    <button type="button" class="btn btn-xs btn-default" id="refreshAct"><i class="fa fa-refresh fa-fw"></i></button>
                    <button type="button" class="btn btn-xs btn-default" id="downloadAct"><i class="fa fa-download fa-fw"></i></button>
                    <button type="button" class="btn btn-xs btn-default" id="clearAct"><i class="fa fa-trash fa-fw"></i></button>
                </span>
            </div>
            <div style="padding: 14px;">
                <textarea id="log-viewer" class="form-control" rows="30" readonly
                          style="font-family: Menlo, Monaco, Consolas, 'Courier New', monospace; font-size: 13px; white-space: pre; overflow-wrap: normal;"></textarea>
            </div>
        </div>
    </section>
</div>
