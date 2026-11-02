{#
 # os-mihomo 二次开发 —— 概览（仪表盘）
 #
 # 全部数据经 /api/mihomo/* 由服务端从 loopback 控制器取回；
 # 页面不包含 iframe，也不要求浏览器直连 :9090。
 #
 # Copyright (C) 2026  os-mihomo contributors
 # All rights reserved.
 # 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 #}
{% set lang = mihomoLang %}


<script src="{{ cache_safe('/ui/js/chart.umd.min.js') }}"></script>
<script src="{{ cache_safe('/js/mihomo/ui.js') }}"></script>

<script>
    $(document).ready(function () {
        /* ------------------------------------------------------------------ *
         * 工具函数
         * ------------------------------------------------------------------ */
        function fmtBytes(bytes) {
            return MihomoUI.formatBytes(bytes);
        }

        function fmtRate(bytesPerSecond) {
            return fmtBytes(bytesPerSecond) + '/s';
        }

        function fmtCount(value) {
            return (Number(value) || 0).toLocaleString();
        }

        function actionFailed(data) {
            $('#dashboard-action-state').text(MihomoUI.decodeApiText(data && data.message) || {{ lang._('The operation failed. Please try again.') | json_encode }});
        }

        function delayClass(delay) {
            if (delay === null || delay === undefined || delay <= 0) {
                return 'label-danger';
            } else if (delay < 200) {
                return 'label-success';
            } else if (delay < 500) {
                return 'label-warning';
            }
            return 'label-danger';
        }

        function delayText(delay) {
            if (delay === null || delay === undefined) {
                return '—';
            } else if (delay <= 0) {
                return ({{ lang._('timeout') | json_encode }});
            }
            return delay + ' ms';
        }

        /* ------------------------------------------------------------------ *
         * 服务状态：使用 OPNsense 标准服务控件（页面标题右侧）
         * ------------------------------------------------------------------ */
        updateServiceControlUI('mihomo');

        /* ------------------------------------------------------------------ *
         * 服务状态提示（标准控件在标题栏；这里补充 disabled 状态的说明）
         * ------------------------------------------------------------------ */
        function loadServiceState(done) {
            ajaxGet('/api/mihomo/service/status', {}, function (data, status) {
                const ok = status === 'success' && data && data.status;
                if (done) { done(!!ok); }
                if (!ok) { return; }
                const $box = $('#mihomo-service-state');
                if (data['status'] === 'disabled') {
                    $box.html('<div class="alert alert-warning">'
                        + '<i class="fa fa-power-off fa-fw"></i> '
                        + ('<b>' + {{ lang._('The service is not enabled at boot.') | json_encode }} + '</b> ')
                        + ({{ lang._('Use %sSettings%s to enable it, then start it from the controls in the page header.') | format('<a href="/ui/mihomo/settings">', '</a>') | json_encode }})
                        + '</div>');
                } else if (data['status'] === 'stopped') {
                    $box.html('<div class="alert alert-danger">'
                        + '<i class="fa fa-stop-circle fa-fw"></i> '
                        + ({{ lang._('The service is stopped. Use the start button in the page header to bring it up.') | json_encode }})
                        + '</div>');
                } else {
                    $box.empty();
                }
            });
        }

        /* ------------------------------------------------------------------ *
         * 运行态概览
         * ------------------------------------------------------------------ */
        let gTrafficChart = null;
        let processMemory = null;
        $(document).on('mihomo:runtime', function (event, data) {
            processMemory = data.process && data.process.rss > 0 ? data.process.rss : null;
            $('#stat-memory').text(processMemory !== null ? fmtBytes(processMemory) : {{ lang._('Unavailable') | json_encode }});
        });
        let storedHistory = [];
        try { storedHistory = JSON.parse(sessionStorage.getItem('mihomo.traffic.v1') || '[]'); } catch (error) { /* Optional cache. */ }
        const trafficHistory = new MihomoUI.TrafficHistory(storedHistory);
        let trafficRange = 60;
        let lastMetadata = 0;
        let lastHistorySave = 0;

        function drawTraffic() {
            if (!gTrafficChart) { return; }
            const samples = trafficHistory.window(trafficRange, Date.now());
            gTrafficChart.data.labels = samples.map(function (point) {
                return new Date(point.time).toLocaleTimeString([], {hour: '2-digit', minute: '2-digit', second: trafficRange <= 300 ? '2-digit' : undefined});
            });
            gTrafficChart.data.datasets[0].data = samples.map(function (point) { return point.down; });
            gTrafficChart.data.datasets[1].data = samples.map(function (point) { return point.up; });
            gTrafficChart.update('none');
            $('#traffic-history-note').text(samples.length < 2
                ? {{ lang._('Waiting for traffic samples.') | json_encode }}
                : {{ lang._('History is collected while this page is open. Gaps indicate missing samples.') | json_encode }});
        }

        $('#traffic-range').on('change', function () {
            trafficRange = Number(this.value);
            drawTraffic();
        });

        function renderOverview(data) {
            const runtime = data['runtime'] || {};
            const controller = data['controller'] || {};
            const config = data['config'] || {};

            $('#stat-connections').text(fmtCount(runtime['connections']));
            $('#stat-download').text(fmtBytes(runtime['downloadTotal']));
            $('#stat-upload').text(fmtBytes(runtime['uploadTotal']));
            $('#stat-memory').text(processMemory !== null ? fmtBytes(processMemory) : {{ lang._('Unavailable') | json_encode }});

            if (controller['alive']) {
                if (controller.version !== undefined) { $('#mihomo-version').text(controller.version || '—'); }
            } else {
                $('#mihomo-version').text(({{ lang._('not running') | json_encode }}));
            }

            if (runtime.mode !== undefined && !$('#mode-select').data('user-changed')) {
                $('#mode-select').val(runtime['mode'] || '');
            }

            const now = Date.now();
            const rate = trafficHistory.add(now, runtime['downloadTotal'], runtime['uploadTotal'], runtime['ready'] && controller['alive']);
            $('#stat-rate-down').text(rate.down === null ? '—' : fmtRate(rate.down));
            $('#stat-rate-up').text(rate.up === null ? '—' : fmtRate(rate.up));
            if (now - lastHistorySave > 10000) {
                try { sessionStorage.setItem('mihomo.traffic.v1', JSON.stringify(trafficHistory.samples)); } catch (error) { /* Storage may be disabled. */ }
                lastHistorySave = now;
            }
            drawTraffic();
        }

        function loadOverview(done) {
            const metadata = Date.now() - lastMetadata >= 30000;
            ajaxGet('/api/mihomo/dashboard/overview', {metadata: metadata ? 1 : 0}, function (data, status) {
                const ok = status === 'success' && data && data.runtime;
                if (ok) {
                    if (metadata) { lastMetadata = Date.now(); }
                    renderOverview(data);
                } else {
                    trafficHistory.add(Date.now(), null, null, false);
                    $('#stat-rate-down, #stat-rate-up').text('—');
                    drawTraffic();
                }
                if (done) { done(!!ok && data.runtime.ready); }
            });
        }

        /* ------------------------------------------------------------------ *
         * 代理分组
         * ------------------------------------------------------------------ */
        function renderGroups(data) {
            const $box = $('#proxy-groups');
            if (!data['ready']) {
                $box.html('<div class="text-muted" style="padding: 12px;">'
                    + ('<i class="fa fa-plug fa-fw"></i> ' + {{ lang._('The controller is not reachable. Start the service to see proxy groups.') | json_encode }})
                    + '</div>');
                return;
            }
            const groups = data['groups'] || [];
            if (groups.length === 0) {
                $box.html(('<div class="text-muted" style="padding: 12px;">' + {{ lang._('No proxy groups are defined in the configuration.') | json_encode }} + '</div>'));
                return;
            }

            MihomoUI.renderProxyGroups($box[0], groups, {
                testGroup: {{ lang._('Test all nodes in this group') | json_encode }},
                testNode: {{ lang._('Test node latency') | json_encode }}
            }, delayText, delayClass);
        }

        let testing = false;
        function testNodes(names) {
            if (testing || !names.length) { return; }
            testing = true;
            $('#proxy-groups .cmd-test, #proxy-groups .cmd-test-group').prop('disabled', true);
            const progress = function (state) {
                $('#proxy-test-state').text({{ lang._('Latency tests') | json_encode }} + ': ' + state.completed + '/' + state.total
                    + ' · ' + {{ lang._('Failed') | json_encode }} + ': ' + state.failed);
            };
            progress({completed: 0, total: names.length, failed: 0});
            MihomoUI.runLimited(names, 3, function (name, done) {
                ajaxCall('/api/mihomo/dashboard/test_delay', {name: name}, function (data, status) {
                    done(status === 'success' && data && data.status === 'ok');
                });
            }, progress, function () {
                testing = false;
                $('#proxy-groups .cmd-test, #proxy-groups .cmd-test-group').prop('disabled', false);
                groupsPoller.refresh();
            });
        }
        $('#proxy-groups').on('click', '.cmd-test', function () { testNodes([$(this).attr('data-name')]); });
        $('#proxy-groups').on('click', '.cmd-test-group', function () {
            const names = [];
            $(this).closest('.content-box').find('.cmd-test').each(function () { names.push($(this).attr('data-name')); });
            testNodes(Array.from(new Set(names)));
        });
        $('#proxy-groups').on('click', '.cmd-select', function () {
            const $button = $(this), $item = $button.closest('li');
            $button.prop('disabled', true);
            ajaxCall('/api/mihomo/dashboard/select_proxy', {group: $item.attr('data-group'), member: $item.attr('data-member')}, function (data, status) {
                $button.prop('disabled', false);
                if (status === 'success' && data && data.status === 'ok') { $('#dashboard-action-state').empty(); groupsPoller.refresh(); }
                else { actionFailed(data); }
            });
        });

        function loadGroups(done) {
            if (testing) { done(true); return; }
            ajaxGet('/api/mihomo/dashboard/proxies', {}, function (data, status) {
                const ok = status === 'success' && data && data.ready;
                if (data && status === 'success') { renderGroups(data); }
                if (!ok) { $('#proxy-test-state').text({{ lang._('Read failed. The last result is retained.') | json_encode }}); }
                done(!!ok);
            });
        }

        /* ------------------------------------------------------------------ *
         * 运行模式
         * ------------------------------------------------------------------ */
        $('#mode-select').change(function () {
            const mode = $(this).val();
            $(this).data('user-changed', true);
            ajaxCall('/api/mihomo/dashboard/set_mode', { mode: mode }, function (data, status) {
                if (status === 'success' && data && data.status === 'ok') { $('#dashboard-action-state').empty(); }
                else { actionFailed(data); }
                lastMetadata = 0;
                overviewPoller.refresh();
                setTimeout(function () {
                    $('#mode-select').data('user-changed', false);
                    lastMetadata = 0; overviewPoller.refresh();
                }, 2000);
            });
        });

        /* ------------------------------------------------------------------ *
         * 活动连接表格
         * ------------------------------------------------------------------ */
        $("#grid-connections").UIBootgrid({
            'search': '/api/mihomo/dashboard/connections',
            'options': {
                'rowSelect': false,
                'multiSelect': false,
                'formatters': {
                    'bytesformatter': function (column, row) {
                        return fmtBytes(row[column.id]);
                    },
                    'timeformatter': function (column, row) {
                        if (!row.start) {
                            return '';
                        }
                        const started = new Date(row.start);
                        const seconds = Math.max(Math.round((Date.now() - started.getTime()) / 1000), 0);
                        let human = seconds + 's';
                        if (seconds >= 3600) {
                            human = Math.floor(seconds / 3600) + 'h' + Math.floor((seconds % 3600) / 60) + 'm';
                        } else if (seconds >= 60) {
                            human = Math.floor(seconds / 60) + 'm' + (seconds % 60) + 's';
                        }
                        return MihomoUI.element(document, 'span', {'data-toggle': 'tooltip', title: started.toLocaleString()}, human).outerHTML;
                    },
                    'closeformatter': function (column, row) {
                        const button = MihomoUI.element(document, 'button', {type: 'button', class: 'btn btn-xs btn-default cmd-close-connection',
                            'data-id': MihomoUI.decodeApiText(row.id), 'aria-label': {{ lang._('Close connection') | json_encode }}, title: {{ lang._('Close connection') | json_encode }}});
                        button.appendChild(MihomoUI.element(document, 'i', {class: 'fa fa-times fa-fw', 'aria-hidden': 'true'}));
                        return button.outerHTML;
                    }
                }
            }
        }).on('loaded.rs.jquery.bootgrid', function () {
            $('[data-toggle="tooltip"]').tooltip({ 'container': 'body' });
            $('.cmd-close-connection').off('click').on('click', function () {
                closeConnections($(this).attr('data-id'));
            });
        });

        function closeConnections(id) {
            ajaxCall('/api/mihomo/dashboard/close_connection', {id: id}, function (data, status) {
                if (status === 'success' && data && data.status === 'ok') {
                    $('#dashboard-action-state').empty();
                    $('#grid-connections').bootgrid('reload'); overviewPoller.refresh();
                } else { actionFailed(data); }
            });
        }
        $('#close-all-connections').click(function () { closeConnections(''); });

        /* ------------------------------------------------------------------ *
         * 流量图 + 轮询
         * ------------------------------------------------------------------ */
        gTrafficChart = new Chart($('#traffic-chart')[0].getContext('2d'), {
            'type': 'line',
            'data': {
                'labels': [],
                'datasets': [
                    {
                        'label': ({{ lang._('Download') | json_encode }}),
                        'data': [],
                        'borderColor': 'currentColor',
                        'backgroundColor': 'transparent',
                        'borderWidth': 2,
                        'pointRadius': 0,
                        'fill': false, 'spanGaps': false
                    },
                    {
                        'label': ({{ lang._('Upload') | json_encode }}),
                        'data': [],
                        'borderColor': 'currentColor',
                        'backgroundColor': 'transparent',
                        'borderWidth': 2,
                        'pointRadius': 0,
                        'fill': false, 'spanGaps': false
                    }
                ]
            },
            'options': {
                'responsive': true,
                'maintainAspectRatio': false,
                'animation': false,
                'elements': { 'line': { 'tension': 0.3 } },
                'scales': {
                    'y': {
                        'beginAtZero': true,
                        'ticks': {
                            'callback': function (value) {
                                return fmtBytes(value) + '/s';
                            }
                        }
                    },
                    'x': { 'ticks': { 'maxTicksLimit': 8 } }
                },
                'plugins': { 'legend': { 'display': true } }
            }
        });

        function updateChartTheme() {
            const colors = MihomoUI.theme(document.getElementById('traffic-panel'));
            gTrafficChart.data.datasets[0].borderColor = colors.down;
            gTrafficChart.data.datasets[1].borderColor = colors.up;
            gTrafficChart.data.datasets[1].borderDash = [5, 3];
            gTrafficChart.options.color = colors.text;
            gTrafficChart.options.scales.x.ticks.color = colors.text;
            gTrafficChart.options.scales.y.ticks.color = colors.text;
            gTrafficChart.options.scales.x.grid = {color: colors.grid};
            gTrafficChart.options.scales.y.grid = {color: colors.grid};
            gTrafficChart.options.plugins.legend.labels = {color: colors.text};
            gTrafficChart.update('none');
        }
        updateChartTheme();
        new MutationObserver(updateChartTheme).observe(document.documentElement, {attributes: true, attributeFilter: ['class', 'style', 'data-theme']});
        new MutationObserver(updateChartTheme).observe(document.body, {attributes: true, attributeFilter: ['class', 'style', 'data-theme']});
        new MutationObserver(updateChartTheme).observe(document.head, {childList: true, subtree: true, attributes: true, attributeFilter: ['href']});
        document.addEventListener('load', function (event) { if (event.target.tagName === 'LINK') { updateChartTheme(); } }, true);
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateChartTheme);

        const overviewPoller = new MihomoUI.Poller(loadOverview, 2000);
        const groupsPoller = new MihomoUI.Poller(loadGroups, 15000);
        const servicePoller = new MihomoUI.Poller(loadServiceState, 30000);
        const pollers = [overviewPoller, groupsPoller, servicePoller];
        pollers.forEach(poller => poller.refresh());
        document.addEventListener('visibilitychange', function () {
            if (document.hidden) { trafficHistory.add(Date.now(), null, null, false); }
            else { lastMetadata = 0; }
            pollers.forEach(poller => poller.visibilityChanged());
        });
        window.addEventListener('pagehide', () => pollers.forEach(poller => poller.stop()));
    });
</script>

<div class="row">
    <section class="col-xs-12">
        <div id="mihomo-service-state"></div>
        <p id="dashboard-action-state" class="text-danger" role="alert"></p>
    </section>
</div>


<div class="row mihomo-metrics">
    <div class="col-sm-6 col-lg-3"><div class="content-box" style="padding:16px; min-height:100px; margin-bottom:15px;">
        <div class="text-muted">{{ lang._('Active Connections') }}</div>
        <div id="stat-connections" style="font-size:22px; font-variant-numeric:tabular-nums; overflow-wrap:anywhere;">—</div>
    </div></div>
    <div class="col-sm-6 col-lg-3"><div class="content-box" style="padding:16px; min-height:100px; margin-bottom:15px;">
        <div class="text-muted">{{ lang._('Download rate') }}</div>
        <div id="stat-rate-down" style="font-size:22px; font-variant-numeric:tabular-nums; overflow-wrap:anywhere;">—</div>
    </div></div>
    <div class="col-sm-6 col-lg-3"><div class="content-box" style="padding:16px; min-height:100px; margin-bottom:15px;">
        <div class="text-muted">{{ lang._('Upload rate') }}</div>
        <div id="stat-rate-up" style="font-size:22px; font-variant-numeric:tabular-nums; overflow-wrap:anywhere;">—</div>
    </div></div>
    <div class="col-sm-6 col-lg-3"><div class="content-box" style="padding:16px; min-height:100px; margin-bottom:15px;">
        <div class="text-muted">{{ lang._('Process memory (RSS)') }}</div>
        <div id="stat-memory" style="font-size:22px; font-variant-numeric:tabular-nums; overflow-wrap:anywhere;">—</div>
    </div></div>
</div>
<div class="row"><section class="col-xs-12"><div class="content-box" style="padding:10px 14px; display:flex; flex-wrap:wrap; gap:12px 24px; margin-bottom:15px;">
    <span>{{ lang._('Downloaded') }}: <span id="stat-download">—</span></span>
    <span>{{ lang._('Uploaded') }}: <span id="stat-upload">—</span></span>
    <span>{{ lang._('Core version') }}: <span id="mihomo-version">—</span></span>
</div></section></div>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box" id="traffic-panel">
            <div style="padding:12px 14px; display:flex; align-items:center; flex-wrap:wrap; gap:10px;">
                <i class="fa fa-area-chart text-muted"></i> <b>{{ lang._('Traffic') }}</b>
                <span style="margin-left:auto; display:flex; flex-wrap:wrap; align-items:center; gap:8px;">
                    <label for="traffic-range" style="font-weight:normal; margin:0;">{{ lang._('Time range') }}</label>
                    <select id="traffic-range" class="form-control" style="width:auto;">
                        <option value="60">{{ lang._('Last minute') }}</option>
                        <option value="300">{{ lang._('Last 5 minutes') }}</option>
                        <option value="900">{{ lang._('Last 15 minutes') }}</option>
                        <option value="3600">{{ lang._('Last hour') }}</option>
                    </select>
                    <label for="mode-select" style="font-weight: normal;">{{ lang._('Mode') }}:</label>
                    <select id="mode-select" class="form-control" style="width: auto; display: inline-block; height: 28px; padding: 2px 6px;">
                        <option value="">{{ lang._('…') }}</option>
                        <option value="rule">{{ lang._('Rule-based') }}</option>
                        <option value="global">{{ lang._('Global') }}</option>
                        <option value="direct">{{ lang._('Direct') }}</option>
                    </select>
                </span>
            </div>
            <div style="padding: 12px;">
                <div style="height: 200px;">
                    <canvas id="traffic-chart" role="img" aria-label="{{ lang._('Download and upload rates') }}"></canvas>
                </div>
                <p class="text-muted" id="traffic-history-note" role="status" style="margin-top:10px;"></p>
            </div>
        </div>
    </section>
</div>

<div class="row"><section class="col-xs-12">{{ partial('OPNsense/Mihomo/network_status', ['network_id':'overview-network']) }}</section></div>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding: 12px 14px; ">
                <i class="fa fa-sitemap text-muted"></i> <b>{{ lang._('Proxy Groups') }}</b>
            </div>
            <p id="proxy-test-state" class="text-muted" role="status" style="padding:0 12px;"></p>
            <div style="padding: 12px;" id="proxy-groups">
                <div class="text-muted">{{ lang._('Loading …') }}</div>
            </div>
        </div>
    </section>
</div>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding: 12px 14px; ">
                <i class="fa fa-exchange text-muted"></i> <b>{{ lang._('Active Connections') }}</b>
                <span class="pull-right">
                    <button type="button" id="close-all-connections" class="btn btn-xs btn-default">
                        <i class="fa fa-times-circle fa-fw"></i> {{ lang._('Close all') }}
                    </button>
                </span>
            </div>
            <div style="padding: 12px;">
                <div class="table-responsive">
                <table id="grid-connections" class="table table-condensed table-hover table-striped table-responsive" data-editDialog="">
                    <thead>
                        <tr>
                            <th data-column-id="host" data-type="string">{{ lang._('Host') }}</th>
                            <th data-column-id="source" data-width="11em" data-type="string">{{ lang._('Source') }}</th>
                            <th data-column-id="network" data-width="5em" data-type="string">{{ lang._('Network') }}</th>
                            <th data-column-id="type" data-width="5em" data-type="string">{{ lang._('Type') }}</th>
                            <th data-column-id="rule" data-width="10em" data-type="string">{{ lang._('Rule') }}</th>
                            <th data-column-id="chain" data-type="string">{{ lang._('Chain') }}</th>
                            <th data-column-id="download" data-width="7em" data-type="string" data-formatter="bytesformatter">{{ lang._('Download') }}</th>
                            <th data-column-id="upload" data-width="7em" data-type="string" data-formatter="bytesformatter">{{ lang._('Upload') }}</th>
                            <th data-column-id="start" data-width="7em" data-type="string" data-formatter="timeformatter">{{ lang._('Age') }}</th>
                            <th data-column-id="id" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                            <th data-column-id="commands" data-width="4em" data-formatter="closeformatter" data-sortable="false">{{ lang._('Close') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                    </tbody>
                    <tfoot>
                    </tfoot>
                </table>
                </div>
            </div>
        </div>
    </section>
</div>
