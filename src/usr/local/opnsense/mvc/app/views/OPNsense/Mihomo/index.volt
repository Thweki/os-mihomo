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

<script src="{{ cache_safe('/ui/js/chart.umd.min.js') }}"></script>

<script>
    $(document).ready(function () {
        /* ------------------------------------------------------------------ *
         * 工具函数
         * ------------------------------------------------------------------ */
        function fmtBytes(bytes) {
            bytes = Number(bytes) || 0;
            const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
            let idx = 0;
            while (bytes >= 1024 && idx < units.length - 1) {
                bytes /= 1024;
                idx++;
            }
            return (idx === 0 ? bytes : bytes.toFixed(2)) + ' ' + units[idx];
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
                return '{{ lang._('timeout') }}';
            }
            return delay + ' ms';
        }

        /* ------------------------------------------------------------------ *
         * 服务状态：使用 OPNsense 标准服务控件（页面标题右侧）
         * ------------------------------------------------------------------ */
        updateServiceControlUI('mihomo');

        /* ------------------------------------------------------------------ *
         * 安全体检横幅
         * ------------------------------------------------------------------ */
        function renderSafety(data) {
            const $box = $('#mihomo-safety');
            const items = data['items'] || [];
            if (items.length === 0) {
                $box.empty();
                return;
            }
            let worst = 'info';
            let html = '';
            items.forEach(function (item) {
                if (item['level'] === 'danger') {
                    worst = 'danger';
                } else if (item['level'] === 'warning' && worst !== 'danger') {
                    worst = 'warning';
                }
            });
            if (worst === 'info') {
                $box.empty();
                return;
            }
            html += '<div class="alert alert-' + worst + '">';
            html += '<i class="fa fa-exclamation-triangle fa-fw"></i> <b>{{ lang._('Please review before starting the service') }}</b><ul style="margin-bottom:0;margin-top:6px;">';
            items.forEach(function (item) {
                if (item['level'] === 'info') {
                    return;
                }
                html += '<li class="text-' + item['level'] + '"><b>' + escapeHtml(item['title']) + '</b> — ' + escapeHtml(item['detail']) + '</li>';
            });
            html += '</ul></div>';
            $box.html(html);
        }

        function loadSafety() {
            ajaxGet('/api/mihomo/service/safety', {}, renderSafety);
        }

        /* ------------------------------------------------------------------ *
         * 运行态概览
         * ------------------------------------------------------------------ */
        let gTrafficChart = null;
        let gPreviousSample = null;
        let gLabels = [];

        function renderOverview(data) {
            const runtime = data['runtime'] || {};
            const controller = data['controller'] || {};
            const config = data['config'] || {};

            $('#stat-connections').text(fmtCount(runtime['connections']));
            $('#stat-download').text(fmtBytes(runtime['downloadTotal']));
            $('#stat-upload').text(fmtBytes(runtime['uploadTotal']));
            $('#stat-memory').text(fmtBytes(runtime['memory']));
            $('#stat-version').text(controller['meta'] === true ? 'Meta' : (controller['alive'] ? 'core' : '—'));

            if (controller['alive']) {
                $('#mihomo-version').text(controller['version'] || '—');
            } else {
                $('#mihomo-version').text('{{ lang._('not running') }}');
            }

            if (!$('#mode-select').data('user-changed')) {
                $('#mode-select').val(runtime['mode'] || '');
            }

            const now = Date.now();
            let inRate = 0;
            let outRate = 0;
            if (gPreviousSample !== null) {
                const seconds = Math.max((now - gPreviousSample.time) / 1000, 0.5);
                inRate = Math.max((runtime['downloadTotal'] - gPreviousSample.download) / seconds, 0);
                outRate = Math.max((runtime['uploadTotal'] - gPreviousSample.upload) / seconds, 0);
            }
            gPreviousSample = { time: now, download: runtime['downloadTotal'] || 0, upload: runtime['uploadTotal'] || 0 };

            $('#stat-rate-down').text(fmtRate(inRate));
            $('#stat-rate-up').text(fmtRate(outRate));

            if (gTrafficChart !== null) {
                const label = new Date(now).toLocaleTimeString();
                gLabels.push(label);
                gTrafficChart.data.labels.push(label);
                gTrafficChart.data.datasets[0].data.push(Math.round(inRate));
                gTrafficChart.data.datasets[1].data.push(Math.round(outRate));
                const maxPoints = 60;
                if (gLabels.length > maxPoints) {
                    gLabels.shift();
                    gTrafficChart.data.labels.shift();
                    gTrafficChart.data.datasets.forEach(function (dataset) {
                        dataset.data.shift();
                    });
                }
                gTrafficChart.update('none');
            }
        }

        function loadOverview() {
            ajaxGet('/api/mihomo/dashboard/overview', {}, renderOverview);
        }

        /* ------------------------------------------------------------------ *
         * 代理分组
         * ------------------------------------------------------------------ */
        function renderGroups(data) {
            const $box = $('#proxy-groups');
            if (!data['ready']) {
                $box.html('<div class="text-muted" style="padding: 12px;">'
                    + '<i class="fa fa-plug fa-fw"></i> {{ lang._('The controller is not reachable. Start the service to see proxy groups.') }}'
                    + '</div>');
                return;
            }
            const groups = data['groups'] || [];
            if (groups.length === 0) {
                $box.html('<div class="text-muted" style="padding: 12px;">{{ lang._('No proxy groups are defined in the configuration.') }}</div>');
                return;
            }

            let html = '<div class="row">';
            groups.forEach(function (group) {
                html += '<div class="col-md-6 col-lg-4" style="margin-bottom: 15px;">';
                html += '<div class="content-box" style="height: 100%; margin-bottom: 0;">';
                html += '<div style="padding: 10px 12px; border-bottom: 1px solid #eeeeee;">';
                html += '<b>' + escapeHtml(group['name']) + '</b> ';
                html += '<span class="label label-opnsense label-opnsense-sm label-info">' + escapeHtml(group['type']) + '</span>';
                html += '<span class="pull-right">';
                html += '<button type="button" class="btn btn-xs btn-default cmd-test-group" data-group="' + escapeHtml(group['name']) + '"><i class="fa fa-tachometer fa-fw"></i></button>';
                html += '</span>';
                html += '</div>';
                html += '<ul class="list-group" style="margin-bottom: 0; max-height: 320px; overflow-y: auto;">';
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
                        'label': '{{ lang._('Download') }}',
                        'data': [],
                        'borderColor': '#3c8dbc',
                        'backgroundColor': 'rgba(60, 141, 188, 0.15)',
                        'borderWidth': 1,
                        'pointRadius': 0,
                        'fill': true
                    },
                    {
                        'label': '{{ lang._('Upload') }}',
                        'data': [],
                        'borderColor': '#a94442',
                        'backgroundColor': 'rgba(169, 68, 66, 0.15)',
                        'borderWidth': 1,
                        'pointRadius': 0,
                        'fill': true
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

        function refreshAll() {
            loadOverview();
        }

        loadSafety();
        loadOverview();
        loadGroups();
        refreshAll();

        setInterval(loadOverview, 2000);
        setInterval(loadGroups, 15000);
        setInterval(loadSafety, 60000);
    });
</script>

<div class="row">
    <section class="col-xs-12">
        <div id="mihomo-safety"></div>
    </section>
</div>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div class="container-fluid" style="padding-left: 0; padding-right: 0;">
                <div class="row">
                    <div class="col-sm-6 col-md-2" style="margin-bottom: 10px;">
                        <div style="text-align: center;">
                            <div class="text-muted" style="font-size: 11px; text-transform: uppercase; letter-spacing: .5px;">{{ lang._('Active Connections') }}</div>
                            <div style="font-size: 26px; font-weight: 600;" id="stat-connections">—</div>
                        </div>
                    </div>
                    <div class="col-sm-6 col-md-2" style="margin-bottom: 10px;">
                        <div style="text-align: center;">
                            <div class="text-muted" style="font-size: 11px; text-transform: uppercase; letter-spacing: .5px;">{{ lang._('Download') }} / {{ lang._('Upload') }}</div>
                            <div style="font-size: 15px; font-weight: 600; color: #3c8dbc;" id="stat-rate-down">—</div>
                            <div style="font-size: 15px; font-weight: 600; color: #a94442;" id="stat-rate-up">—</div>
                        </div>
                    </div>
                    <div class="col-sm-6 col-md-2" style="margin-bottom: 10px;">
                        <div style="text-align: center;">
                            <div class="text-muted" style="font-size: 11px; text-transform: uppercase; letter-spacing: .5px;">{{ lang._('Total Downloaded') }}</div>
                            <div style="font-size: 20px; font-weight: 600;" id="stat-download">—</div>
                        </div>
                    </div>
                    <div class="col-sm-6 col-md-2" style="margin-bottom: 10px;">
                        <div style="text-align: center;">
                            <div class="text-muted" style="font-size: 11px; text-transform: uppercase; letter-spacing: .5px;">{{ lang._('Total Uploaded') }}</div>
                            <div style="font-size: 20px; font-weight: 600;" id="stat-upload">—</div>
                        </div>
                    </div>
                    <div class="col-sm-6 col-md-2" style="margin-bottom: 10px;">
                        <div style="text-align: center;">
                            <div class="text-muted" style="font-size: 11px; text-transform: uppercase; letter-spacing: .5px;">{{ lang._('Memory In Use') }}</div>
                            <div style="font-size: 20px; font-weight: 600;" id="stat-memory">—</div>
                        </div>
                    </div>
                    <div class="col-sm-6 col-md-2" style="margin-bottom: 10px;">
                        <div style="text-align: center;">
                            <div class="text-muted" style="font-size: 11px; text-transform: uppercase; letter-spacing: .5px;">{{ lang._('Core Version') }}</div>
                            <div style="font-size: 20px; font-weight: 600;" id="mihomo-version">—</div>
                            <div class="text-muted" style="font-size: 11px;" id="stat-version">—</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </section>
</div>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding: 12px 14px; border-bottom: 1px solid #eeeeee;">
                <i class="fa fa-area-chart text-muted"></i> <b>{{ lang._('Traffic') }}</b>
                <span class="pull-right">
                    <label style="font-weight: normal;">{{ lang._('Mode') }}:</label>
                    <select id="mode-select" class="form-control" style="width: auto; display: inline-block; height: 28px; padding: 2px 6px;">
                        <option value="">{{ lang._('…') }}</option>
                        <option value="rule">rule</option>
                        <option value="global">global</option>
                        <option value="direct">direct</option>
                    </select>
                </span>
            </div>
            <div style="padding: 12px;">
                <div style="height: 200px;">
                    <canvas id="traffic-chart"></canvas>
                </div>
            </div>
        </div>
    </section>
</div>

<div class="row">
    <section class="col-xs-12">
        <div class="content-box">
            <div style="padding: 12px 14px; border-bottom: 1px solid #eeeeee;">
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
            <div style="padding: 12px 14px; border-bottom: 1px solid #eeeeee;">
                <i class="fa fa-exchange text-muted"></i> <b>{{ lang._('Active Connections') }}</b>
                <span class="pull-right">
                    <button type="button" id="close-all-connections" class="btn btn-xs btn-default">
                        <i class="fa fa-times-circle fa-fw"></i> {{ lang._('Close all') }}
                    </button>
                </span>
            </div>
            <div style="padding: 12px;">
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
    </section>
</div>
