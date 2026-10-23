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

        function escapeHtml(text) {
            return $('<div>').text(text === undefined || text === null ? '' : String(text)).html();
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
        function loadServiceState() {
            ajaxGet('/api/mihomo/service/status', {}, function (data) {
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
        let storedHistory = [];
        try { storedHistory = JSON.parse(sessionStorage.getItem('mihomo.traffic.v1') || '[]'); } catch (error) { /* Optional cache. */ }
        const trafficHistory = new MihomoUI.TrafficHistory(storedHistory);
        let trafficRange = 60;
        let overviewPending = false;
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
            $('#stat-memory').text(runtime['memory'] > 0 ? fmtBytes(runtime['memory']) : {{ lang._('Unavailable') | json_encode }});

            if (controller['alive']) {
                $('#mihomo-version').text(controller['version'] || '—');
            } else {
                $('#mihomo-version').text(({{ lang._('not running') | json_encode }}));
            }

            if (!$('#mode-select').data('user-changed')) {
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

        function loadOverview() {
            if (overviewPending) { return; }
            overviewPending = true;
            ajaxGet('/api/mihomo/dashboard/overview', {}, function (data, status) {
                overviewPending = false;
                if (status === 'success' && data && data.runtime) { renderOverview(data); }
                else {
                    trafficHistory.add(Date.now(), null, null, false);
                    $('#stat-rate-down, #stat-rate-up').text('—');
                    drawTraffic();
                }
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

            let html = '<div class="row">';
            groups.forEach(function (group) {
                html += '<div class="col-md-6" style="margin-bottom: 15px;">';
                html += '<div class="content-box" style="height: 300px; margin-bottom: 0; display: flex; flex-direction: column;">';
                html += '<div style="padding: 10px 12px;  flex: 0 0 auto;">';
                html += '<b>' + escapeHtml(group['name']) + '</b> ';
                html += '<span class="label label-opnsense label-opnsense-sm label-info">' + escapeHtml(group['type']) + '</span>';
                html += '<span class="pull-right">';
                html += '<button type="button" class="btn btn-xs btn-default cmd-test-group" data-group="' + escapeHtml(group['name']) + '"><i class="fa fa-tachometer fa-fw"></i></button>';
                html += '</span>';
                html += '</div>';
                html += '<ul class="list-group" style="margin-bottom: 0; flex: 1 1 auto; overflow-y: auto;">';
                group['members'].forEach(function (member) {
                    const selected = member['selected'];
                    html += '<li class="list-group-item' + (selected ? ' active' : '') + '" style="cursor: pointer; padding: 8px 12px;"';
                    html += ' data-group="' + escapeHtml(group['name']) + '" data-member="' + escapeHtml(member['name']) + '">';
                    html += '<span class="cmd-select" style="display:inline-block; width: 100%;">';
                    html += (selected ? '<i class="fa fa-check-circle fa-fw text-success"></i> ' : '<i class="fa fa-circle-o fa-fw text-muted"></i> ');
                    html += escapeHtml(member['name']);
                    html += ' <span class="text-muted" style="font-size: 11px;">' + escapeHtml(member['type']) + '</span>';
                    html += '<span class="label label-opnsense label-opnsense-sm ' + delayClass(member['delay']) + ' pull-right" style="margin-left: 6px;">';
                    html += delayText(member['delay']) + '</span>';
                    html += '<span class="pull-right"><button type="button" class="btn btn-xs btn-default cmd-test" data-name="' + escapeHtml(member['name']) + '"><i class="fa fa-bolt fa-fw"></i></button></span>';
                    html += '</span></li>';
                });
                html += '</ul></div></div>';
            });
            html += '</div>';
            $box.html(html);

            $('.cmd-test').off('click').on('click', function (event) {
                event.stopPropagation();
                const $btn = $(this);
                const name = $btn.data('name');
                $btn.find('i').addClass('fa-spin');
                ajaxCall('/api/mihomo/dashboard/test_delay', { name: name }, function () {
                    $btn.find('i').removeClass('fa-spin');
                    loadGroups();
                });
            });

            $('.cmd-test-group').off('click').on('click', function (event) {
                event.stopPropagation();
                const $btn = $(this);
                const group = $btn.data('group');
                const names = [];
                $btn.closest('.content-box').find('.cmd-test').each(function () {
                    names.push($(this).data('name'));
                });
                $btn.find('i').addClass('fa-spin');
                let pending = names.length;
                if (pending === 0) {
                    $btn.find('i').removeClass('fa-spin');
                    return;
                }
                names.forEach(function (name) {
                    ajaxCall('/api/mihomo/dashboard/test_delay', { name: name }, function () {
                        pending -= 1;
                        if (pending <= 0) {
                            $btn.find('i').removeClass('fa-spin');
                            loadGroups();
                        }
                    });
                });
            });

            $('.cmd-select').off('click').on('click', function () {
                const $item = $(this).closest('li');
                const group = $item.data('group');
                const member = $item.data('member');
                ajaxCall('/api/mihomo/dashboard/select_proxy', { group: group, member: member }, function (data) {
                    if (data['status'] === 'ok') {
                        loadGroups();
                    }
                });
            });
        }

        function loadGroups() {
            ajaxGet('/api/mihomo/dashboard/proxies', {}, renderGroups);
        }

        /* ------------------------------------------------------------------ *
         * 运行模式
         * ------------------------------------------------------------------ */
        $('#mode-select').change(function () {
            const mode = $(this).val();
            $(this).data('user-changed', true);
            ajaxCall('/api/mihomo/dashboard/set_mode', { mode: mode }, function (data) {
                if (data['status'] === 'ok') {
                    loadOverview();
                }
                setTimeout(function () {
                    $('#mode-select').data('user-changed', false);
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
                        return '<span data-toggle="tooltip" title="' + started.toLocaleString() + '">' + human + '</span>';
                    },
                    'closeformatter': function (column, row) {
                        return '<button type="button" class="btn btn-xs btn-default cmd-close-connection" data-id="'
                            + escapeHtml(row.id) + '"><i class="fa fa-times fa-fw"></i></button>';
                    }
                }
            }
        }).on('loaded.rs.jquery.bootgrid', function () {
            $('[data-toggle="tooltip"]').tooltip({ 'container': 'body' });
            $('.cmd-close-connection').off('click').on('click', function () {
                ajaxCall('/api/mihomo/dashboard/close_connection', { id: $(this).data('id') }, function () {
                    $('#grid-connections').bootgrid('reload');
                    loadOverview();
                });
            });
        });

        $('#close-all-connections').click(function () {
            ajaxCall('/api/mihomo/dashboard/close_connection', { id: '' }, function () {
                $('#grid-connections').bootgrid('reload');
                loadOverview();
            });
        });

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

        loadOverview();
        loadGroups();
        loadServiceState();

        setInterval(loadOverview, 2000);
        setInterval(loadGroups, 15000);
        setInterval(loadServiceState, 30000);
    });
</script>

<div class="row">
    <section class="col-xs-12">
        <div id="mihomo-service-state"></div>
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
        <div class="text-muted">{{ lang._('Memory') }}</div>
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

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding: 12px 14px; ">
                <i class="fa fa-sitemap text-muted"></i> <b>{{ lang._('Proxy Groups') }}</b>
            </div>
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
