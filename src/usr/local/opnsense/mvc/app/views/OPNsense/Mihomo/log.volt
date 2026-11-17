{#
 # os-mihomo 二次开发 —— 日志
 #
 # 日志文件由 root 拥有，读取统一走 configd，因此不需要放宽任何文件权限。
 #
 # Copyright (C) 2026  os-mihomo contributors
 # All rights reserved.
 # 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 #}
{% set lang = mihomoLang %}
<script src="{{ cache_safe('/js/mihomo/ui.js') }}"></script>


<script>
    $(document).ready(function () {
        let allLines = [], pending = false, queued = false, queuedScroll = false;
        let lastContent = null;
        function withoutTimestamp(line) {
            // Only known leading core/subscription timestamps; never strip dates in messages.
            return line.replace(/^(?:time="\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})"|\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\])[ \t]+/, '');
        }
        function renderLog() {
            const query = $('#log-filter').val().toLocaleLowerCase();
            const level = $('#log-level').val();
            const lines = allLines.filter(line => (level === 'all' || MihomoUI.logLevel(line) === level)
                && (!query || line.toLocaleLowerCase().includes(query)));
            const visible = $('#log-hide-timestamps').prop('checked') ? lines.map(withoutTimestamp) : lines;
            $('#log-viewer').val(visible.join('\n'));
            $('#log-match-state').text(!allLines.length ? {{ lang._('No log entries yet.') | json_encode }}
                : !lines.length ? {{ lang._('No matching log entries.') | json_encode }} : String(lines.length) + ' / ' + String(allLines.length));
        }
        $('#log-filter').on('input', renderLog);
        $('#log-level').change(renderLog);
        $('#log-wrap').prop('checked', true).on('change', function () {
            const $viewer = $('#log-viewer');
            const atBottom = $viewer[0].scrollHeight - $viewer.scrollTop() - $viewer.outerHeight() < 40;
            const wrap = $('#log-wrap').prop('checked');
            // Change presentation only: retain the text, selection and logical line counts.
            $viewer.prop('wrap', wrap ? 'soft' : 'off').css({
                'white-space': wrap ? 'pre-wrap' : 'pre',
                'overflow-wrap': wrap ? 'anywhere' : 'normal'
            });
            if (atBottom) {
                $viewer.scrollTop($viewer[0].scrollHeight);
            }
        });
        $('#log-hide-timestamps').change(function () {
            const top = $('#log-viewer').scrollTop();
            renderLog();
            $('#log-viewer').scrollTop(top);
        });
        function refreshLogs(scroll) {
            if (pending) { queued = true; queuedScroll = queuedScroll || scroll; return; }
            pending = true;
            const key = $('#log-source').val();
            const count = $('#log-lines').val();
            ajaxGet('/api/mihomo/log/tail', { 'key': key, 'lines': count }, function (data, status) {
                pending = false;
                const stale = key !== $('#log-source').val() || count !== $('#log-lines').val();
                const refreshAgain = queued, nextScroll = queuedScroll;
                queued = false; queuedScroll = false;
                if (stale) {
                    refreshLogs(true);
                    return;
                }
                if (status !== 'success' || !data || data.status !== 'ok') {
                    $('#log-state').text({{ lang._('Could not read the log. Try refreshing.') | json_encode }});
                    if (refreshAgain) { refreshLogs(nextScroll); }
                    return;
                }
                $('#log-state').text({{ lang._('Last read') | json_encode }} + ' · ' + new Date().toLocaleTimeString());
                const $viewer = $('#log-viewer');
                // Compare before decoding/filtering; idle polls need no textarea or layout work.
                if (data.content !== lastContent) {
                    const content = MihomoUI.decodeApiText(data.content);
                    const atBottom = $viewer[0].scrollHeight - $viewer.scrollTop() - $viewer.outerHeight() < 40;
                    allLines = content ? content.replace(/\n$/, '').split('\n') : [];
                    renderLog();
                    lastContent = data.content;
                    scroll = scroll || atBottom;
                }
                if (scroll) {
                    $viewer.scrollTop($viewer[0].scrollHeight);
                }
                if (refreshAgain) { refreshLogs(nextScroll); }
            });
        }

        $('#log-source').change(function () {
            lastContent = null;
            allLines = []; renderLog();
            $('#log-state').text({{ lang._('Loading …') | json_encode }});
            refreshLogs(true);
        });
        $('#log-lines').change(function () { refreshLogs(true); });
        $('#refreshAct').click(function () { refreshLogs(true); });
        $('#downloadAct').click(function () {
            const key = $('#log-source').val();
            ajaxGet('/api/mihomo/log/tail', { 'key': key, 'lines': 5000 }, function (data, status) {
                if (status !== 'success' || !data || data.status !== 'ok') { $('#log-state').text({{ lang._('Read failed. The last result is retained.') | json_encode }}); return; }
                const blob = new Blob([MihomoUI.decodeApiText(data['content'])], { 'type': 'text/plain' });
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
                'title': ({{ lang._('Clear log?') | json_encode }}),
                'message': ({{ lang._('The selected log file will be emptied.') | json_encode }}),
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
        setInterval(function () { if ($('#log-auto-refresh').prop('checked') && !document.hidden) { refreshLogs(false); } }, 5000);
    });
</script>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding:12px 14px; display:flex; flex-wrap:wrap; gap:10px; align-items:center;">
                <b><i class="fa fa-file-text-o text-muted"></i> {{ lang._('Log File') }}</b>
                <span style="margin-left:auto; display:flex; flex-wrap:wrap; gap:6px; max-width:100%;">
                    <select aria-label="{{ lang._('Log source') }}" id="log-source" class="form-control" style="width: auto; display: inline-block; height: 28px; padding: 2px 6px;">
                        <option value="mihomo">{{ lang._('Core log') }} — /var/log/mihomo.log</option>
                        <option value="subscription">{{ lang._('Subscription log') }} — /var/log/mihomo_sub.log</option>
                    </select>
                    <select aria-label="{{ lang._('Lines') }}" id="log-lines" class="form-control" style="width: auto; display: inline-block; height: 28px; padding: 2px 6px;">
                        <option value="100">100</option>
                        <option value="300" selected="selected">300</option>
                        <option value="1000">1000</option>
                        <option value="3000">3000</option>
                    </select>
                    <button type="button" class="btn btn-xs btn-default" id="refreshAct" title="{{ lang._('Refresh') }}" aria-label="{{ lang._('Refresh') }}"><i class="fa fa-refresh fa-fw"></i></button>
                    <button type="button" class="btn btn-xs btn-default" id="downloadAct" title="{{ lang._('Download log') }}" aria-label="{{ lang._('Download log') }}"><i class="fa fa-download fa-fw"></i></button>
                    <button type="button" class="btn btn-xs btn-default" id="clearAct" title="{{ lang._('Clear Log') }}" aria-label="{{ lang._('Clear Log') }}"><i class="fa fa-trash fa-fw"></i></button>
                </span>
            </div>
            <div style="padding: 14px;">
                <div style="display:flex; flex-wrap:wrap; align-items:center; gap:12px; margin-bottom:12px;">
                    <label for="log-filter" style="flex:0 0 auto; white-space:nowrap;">{{ lang._('Filter log') }}</label>
                    <input id="log-filter" type="search" class="form-control" style="flex:1 1 200px; width:auto; max-width:100%;" placeholder="{{ lang._('Filter the loaded lines') }}">
                    <label for="log-level">{{ lang._('Log severity') }}</label>
                    <select id="log-level" class="form-control" style="width:auto;" aria-describedby="log-level-help">
                        <option value="all" selected="selected">{{ lang._('All levels') }}</option>
                        <option value="debug">{{ lang._('Debug') }}</option>
                        <option value="info">{{ lang._('Info') }}</option>
                        <option value="warning">{{ lang._('Warning') }}</option>
                        <option value="error">{{ lang._('Error') }}</option>
                        <option value="fatal">{{ lang._('Fatal') }}</option>
                        <option value="panic">{{ lang._('Panic') }}</option>
                        <option value="unknown">{{ lang._('Unknown level') }}</option>
                    </select>
                    <label style="flex:0 0 auto; white-space:nowrap; font-weight:normal; margin:0;"><input id="log-auto-refresh" type="checkbox" checked> {{ lang._('Auto refresh') }}</label>
                    <label for="log-wrap" style="flex:0 0 auto; white-space:nowrap; font-weight:normal; margin:0;"><input id="log-wrap" type="checkbox" aria-controls="log-viewer" checked> {{ lang._('Wrap lines') }}</label>
                    <label style="flex:0 0 auto; white-space:nowrap; font-weight:normal; margin:0;"><input id="log-hide-timestamps" type="checkbox"> {{ lang._('Hide timestamps') }}</label>
                    <span id="log-match-state" class="text-muted" role="status"></span>
                </div>
                <p id="log-level-help" class="text-muted">{{ lang._('Severity filters only loaded lines. Lines without a recognized level appear under Unknown level. Downloads include all levels.') }}</p>
                <p id="log-state" class="text-muted" role="status"></p>
                <textarea aria-label="{{ lang._('Log contents') }}" id="log-viewer" class="form-control" rows="30" wrap="soft" readonly
                          style="width: 100%; max-width: 100%; font-family: Menlo, Monaco, Consolas, 'Courier New', monospace; font-size: 13px; white-space: pre-wrap; overflow-wrap: anywhere;"></textarea>
            </div>
        </div>
    </section>
</div>
