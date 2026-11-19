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
        function initCompactOverview() {
            const key = 'mihomo.overview.compact.v1';
            const toggle = document.getElementById('compact-overview');
            const overview = document.getElementById('mihomo-overview');
            function apply(enabled) {
                toggle.checked = enabled;
                overview.classList.toggle('mihomo-compact', enabled);
                if (gTrafficChart) { gTrafficChart.resize(); }
            }
            let enabled = false;
            try { enabled = window.localStorage.getItem(key) === '1'; } catch (error) { /* Optional preference. */ }
            apply(enabled);
            toggle.addEventListener('change', function () {
                apply(toggle.checked);
                try {
                    if (toggle.checked) { window.localStorage.setItem(key, '1'); }
                    else { window.localStorage.removeItem(key); }
                } catch (error) { /* Keep the layout usable when storage is unavailable. */ }
            });
        }
        initCompactOverview();
        let processMemory = null;
        $(document).on('mihomo:runtime', function (event, data) {
            processMemory = data.process && data.process.rss > 0 ? data.process.rss : null;
            $('#stat-memory').text(processMemory !== null ? fmtBytes(processMemory) : {{ lang._('Unavailable') | json_encode }});
        });
        let storedHistory = [];
        try { storedHistory = JSON.parse(sessionStorage.getItem('mihomo.traffic.v1') || '[]'); } catch (error) { /* Optional cache. */ }
        const trafficHistory = new MihomoUI.TrafficHistory(storedHistory);
        let trafficRange = 60;
        // Reuse locale formatters across every label and polling redraw.
        const trafficTimeWithSeconds = new Intl.DateTimeFormat([], {hour: '2-digit', minute: '2-digit', second: '2-digit'});
        const trafficTimeWithoutSeconds = new Intl.DateTimeFormat([], {hour: '2-digit', minute: '2-digit'});
        let lastMetadata = 0;
        let lastHistorySave = 0;
        function drawTraffic() {
            if (!gTrafficChart) { return; }
            const samples = trafficHistory.window(trafficRange, Date.now());
            const timeFormat = trafficRange <= 300 ? trafficTimeWithSeconds : trafficTimeWithoutSeconds;
            gTrafficChart.data.labels = samples.map(function (point) {
                return timeFormat.format(point.time);
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

        let latestTotals = null;
        const trafficTotals = new MihomoUI.TrafficTotals();
        let trafficTotalsStatus = null;
        function renderTrafficTotals() {
            const rawBytes = $('#traffic-totals-bytes').prop('checked');
            const totals = trafficTotals.values();
            const download = trafficTotals.baseline ? totals?.download : latestTotals?.downloadTotal;
            const upload = trafficTotals.baseline ? totals?.upload : latestTotals?.uploadTotal;
            $('#stat-download').text(MihomoUI.formatTrafficTotal(download, rawBytes));
            $('#stat-upload').text(MihomoUI.formatTrafficTotal(upload, rawBytes));
            $('#reset-traffic-totals').prop('disabled', !totals);
            $('#restore-traffic-totals').prop('disabled', !trafficTotals.baseline);
            const status = trafficTotals.baseline
                ? {{ lang._('Since reset (this page)') | json_encode }}
                : trafficTotals.restarted
                    ? {{ lang._('Core counters decreased; showing core totals.') | json_encode }}
                    : {{ lang._('Core totals') | json_encode }};
            if (status !== trafficTotalsStatus) {
                $('#traffic-totals-note').text(status);
                trafficTotalsStatus = status;
            }
        }
        // Page visit only; also reset browsers that restore checkbox state on reload.
        $('#traffic-totals-bytes').prop('checked', false).on('change', renderTrafficTotals);
        $('#reset-traffic-totals').on('click', function () {
            trafficTotals.reset();
            renderTrafficTotals();
        });
        $('#restore-traffic-totals').on('click', function () {
            trafficTotals.restore();
            renderTrafficTotals();
        });

        function renderOverview(data) {
            const runtime = data['runtime'] || {};
            const controller = data['controller'] || {};
            const config = data['config'] || {};

            $('#stat-connections').text(fmtCount(runtime['connections']));
            latestTotals = runtime;
            trafficTotals.update(runtime['downloadTotal'], runtime['uploadTotal'], runtime['ready'] && controller['alive']);
            renderTrafficTotals();
            $('#stat-memory').text(processMemory !== null ? fmtBytes(processMemory) : {{ lang._('Unavailable') | json_encode }});

            if (controller['alive']) {
                if (controller.version !== undefined) { $('#mihomo-version').text(controller.version || '—'); }
            } else {
                $('#mihomo-version').text(({{ lang._('not running') | json_encode }}));
            }

            if (runtime.mode !== undefined && !$('#mode-select').data('user-changed')) {
                $('#mode-select').val(runtime['mode'] || '');
            }
            renderModeHint();

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
                    trafficTotals.update(null, null, false);
                    renderTrafficTotals();
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
        const favorites = new MihomoUI.ProxyFavorites();
        let nodeOrder = 'config';
        const collapsedGroups = new Set(); // Page visit only; reload starts expanded.
        let latestGroups = null;
        let renderedGroups = null;
        let proxyQuery = '';
        const hiddenProxyNames = new Set(); // Page visit only; never persisted.
        let showHiddenProxies = false;
        function renderGroups(data) {
            latestGroups = data;
            const $box = $('#proxy-groups');
            if (!data['ready']) {
                renderedGroups = null;
                $('#proxy-filter-state').empty();
                $box.html('<div class="text-muted" style="padding: 12px;">'
                    + ('<i class="fa fa-plug fa-fw"></i> ' + {{ lang._('The controller is not reachable. Start the service to see proxy groups.') | json_encode }})
                    + '</div>');
                return;
            }
            const groups = data['groups'] || [];
            if (groups.length === 0) {
                renderedGroups = null;
                $('#proxy-filter-state').empty();
                $box.html(('<div class="text-muted" style="padding: 12px;">' + {{ lang._('No proxy groups are defined in the configuration.') | json_encode }} + '</div>'));
                return;
            }

            // Polls return fresh objects; retain the DOM while their data is unchanged.
            const snapshot = JSON.stringify([groups, proxyQuery, [...hiddenProxyNames], showHiddenProxies]);
            if (snapshot === renderedGroups) { return; }
            const visible = MihomoUI.filterProxyGroups(groups, proxyQuery);
            $('#proxy-filter-state').text(proxyQuery
                ? (hiddenProxyNames.size && !showHiddenProxies
                    ? {{ lang._('Name matches before hiding') | json_encode }}
                    : {{ lang._('Visible proxy entries') | json_encode }}) + ': ' + visible.matched + '/' + visible.total : '');
            if (!visible.groups.length) {
                const message = MihomoUI.element($box[0].ownerDocument, 'div', {class: 'text-muted', style: 'padding:12px;'},
                    {{ lang._('No proxy names match the filter.') | json_encode }});
                $box[0].replaceChildren(message);
                renderedGroups = snapshot;
                return;
            }
            MihomoUI.renderProxyGroups($box[0], visible.groups, {
                memberCount: {{ lang._('Members: %s') | json_encode }},
                collapseGroup: {{ lang._('Collapse group') | json_encode }},
                expandGroup: {{ lang._('Expand group') | json_encode }},
                testGroup: {{ lang._('Test all nodes in this group') | json_encode }},
                testNode: {{ lang._('Test node latency') | json_encode }},
                copyName: {{ lang._('Copy proxy name') | json_encode }},
                copySelection: {{ lang._('Copy group selection') | json_encode }},
                favoriteGroup: {{ lang._('Favorite group') | json_encode }},
                favoriteProxy: {{ lang._('Favorite proxy') | json_encode }},
                hideProxy: {{ lang._('Hide proxy until reload') | json_encode }},
                restoreProxy: {{ lang._('Restore proxy') | json_encode }},
                allHidden: {{ lang._('All matching proxies in this group are hidden.') | json_encode }}
            }, delayText, delayClass, favorites, nodeOrder, collapsedGroups,
                {hiddenNames: hiddenProxyNames, showHidden: showHiddenProxies});
            if (testing) { $('#proxy-groups .cmd-test, #proxy-groups .cmd-test-group').prop('disabled', true); }
            renderedGroups = snapshot;
        }

        $('#proxy-filter').on('input', function () {
            proxyQuery = MihomoUI.normalizeProxyQuery(this.value);
            if (latestGroups) { renderGroups(latestGroups); }
        });
        $('#proxy-filter-clear').on('click', function () {
            $('#proxy-filter').val('').trigger('input').trigger('focus');
        });

        let exportingSelections = false;
        $('#export-selections').on('click', function () {
            if (exportingSelections) { return; }
            exportingSelections = true;
            $('#export-selections').prop('disabled', true);
            $('#selection-export-panel').prop('hidden', true);
            $('#selection-export-text').val('');
            $('#selection-export-state').text({{ lang._('Reading current group selections…') | json_encode }});
            // A dedicated read avoids exporting stale polling data after a selection change.
            ajaxGet('/api/mihomo/dashboard/proxies', {}, function (data, status) {
                exportingSelections = false;
                $('#export-selections').prop('disabled', false);
                if (status !== 'success' || !data || !data.ready || !Array.isArray(data.groups)) {
                    $('#selection-export-state').text({{ lang._('Could not read current selections. Try exporting again.') | json_encode }});
                    return;
                }
                if (!data.groups.length) {
                    $('#selection-export-state').text({{ lang._('No proxy groups are defined in the configuration.') | json_encode }});
                    return;
                }
                const text = MihomoUI.exportSelections(data.groups, new Date().toISOString());
                $('#selection-export-panel').prop('hidden', false);
                const field = $('#selection-export-text').val(text)[0];
                field.focus();
                field.select();
                $('#selection-export-state').text({{ lang._('Copy the selected JSON with Ctrl+C or Command+C. Export again to refresh it.') | json_encode }});
            });
        });
        $('#selection-export-dismiss').on('click', function () {
            $('#selection-export-panel').prop('hidden', true);
            $('#selection-export-text').val('');
            $('#selection-export-state').empty();
            $('#export-selections')[0].focus();
        });

        let copying = false;
        $('#proxy-groups').on('click', '.cmd-copy', async function () {
            if (copying || this.disabled) { return; }
            copying = true;
            // Capture the clicked snapshot before polling can replace its button.
            const text = this.getAttribute('data-copy-text');
            $('#proxy-copy-fallback').prop('hidden', true);
            $('#proxy-copy-text').val('');
            $('#proxy-copy-state').text({{ lang._('Copying…') | json_encode }});
            const copied = await MihomoUI.copyText(text, navigator.clipboard);
            copying = false;
            $('#proxy-copy-state').text(copied
                ? {{ lang._('Copied to clipboard.') | json_encode }}
                : {{ lang._('Clipboard unavailable. Copy the selected text below.') | json_encode }});
            if (!copied) {
                $('#proxy-copy-fallback').prop('hidden', false);
                const field = $('#proxy-copy-text').val(text)[0];
                field.focus();
                field.select();
            }
        });
        $('#proxy-copy-dismiss').on('click', function () {
            $('#proxy-copy-fallback').prop('hidden', true);
            $('#proxy-copy-text').val('');
            $('#proxy-copy-state').empty();
        });

        function updateProxyVisibility() {
            $('#proxy-hidden-count').text(fmtCount(hiddenProxyNames.size));
            $('#proxy-restore-all').prop('disabled', !hiddenProxyNames.size);
            if (latestGroups) { renderGroups(latestGroups); }
        }
        $('#proxy-groups').on('click', '.cmd-hide-proxy', function () {
            const name = $(this).attr('data-name');
            if (hiddenProxyNames.has(name)) { hiddenProxyNames.delete(name); }
            else { hiddenProxyNames.add(name); }
            updateProxyVisibility();
        });
        $('#proxy-show-hidden').prop('checked', false).on('change', function () {
            showHiddenProxies = this.checked;
            updateProxyVisibility();
        });
        $('#proxy-restore-all').on('click', function () {
            $('#proxy-show-hidden').trigger('focus');
            hiddenProxyNames.clear();
            updateProxyVisibility();
        });

        let testing = false;
        $('#proxy-node-order').on('change', function () {
            nodeOrder = this.value;
            renderedGroups = null;
            if (latestGroups) { renderGroups(latestGroups); }
        });
        $('#proxy-groups').on('click', '.cmd-collapse-group', function () {
            const name = $(this).attr('data-group');
            if (collapsedGroups.has(name)) { collapsedGroups.delete(name); }
            else { collapsedGroups.add(name); }
            renderedGroups = null;
            if (latestGroups) { renderGroups(latestGroups); }
        });
        $('#proxy-groups').on('click', '.cmd-favorite', function () {
            const saved = favorites.toggle($(this).attr('data-kind'), $(this).attr('data-name'));
            $('#proxy-favorites-state').text(saved ? '' : {{ lang._('Favorites could not be saved in this browser. They will last only for this page visit.') | json_encode }});
            renderedGroups = null;
            if (latestGroups) { renderGroups(latestGroups); }
        });
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
            // Filtering and collapsing only change the view, never the group probe scope.
            const groups = latestGroups && latestGroups.ready ? latestGroups.groups || [] : [];
            testNodes(MihomoUI.fullProxyGroupTestNames(groups, $(this).attr('data-group'), favorites, nodeOrder));
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
                const health = ok && data.ready === true ? MihomoUI.summarizeProxyLatency(data.groups) : null;
                const note = health
                    ? {{ lang._('Responding') | json_encode }} + ': ' + fmtCount(health.responding)
                        + ' · ' + {{ lang._('No positive result') | json_encode }} + ': ' + fmtCount(health.noPositive)
                        + ' · ' + {{ lang._('Untested or unknown') | json_encode }} + ': ' + fmtCount(health.unknown)
                    : {{ lang._('Status unavailable') | json_encode }};
                const $summary = $('#proxy-health-summary');
                if ($summary.text() !== note) { $summary.text(note); }
                if (data && status === 'success') { renderGroups(data); }
                if (!ok) { $('#proxy-test-state').text({{ lang._('Read failed. The last result is retained.') | json_encode }}); }
                done(!!ok);
            });
        }

        /* ------------------------------------------------------------------ *
         * 运行模式
         * ------------------------------------------------------------------ */
        function renderModeHint() {
            let hint = '';
            switch ($('#mode-select').val()) {
                case 'rule':
                    hint = {{ lang._('Rule-based: Mihomo follows matching rules to route or block traffic.') | json_encode }};
                    break;
                case 'global':
                    hint = {{ lang._('Global: traffic handled by Mihomo uses the GLOBAL group selection.') | json_encode }};
                    break;
                case 'direct':
                    hint = {{ lang._('Direct: traffic handled by Mihomo connects without a proxy.') | json_encode }};
                    break;
            }
            if ($('#mode-hint').text() !== hint) { $('#mode-hint').text(hint); }
        }

        $('#mode-select').change(function () {
            const mode = $(this).val();
            renderModeHint();
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

        function isCopyAddressText(text) {
            // The controller validates the IP; reject unexpected DOM values as well.
            return typeof text === 'string' && text.length <= 45 && /^[0-9a-f:.]+$/i.test(text);
        }

        function connectionAddressCell(column, row) {
            const source = column.id === 'source';
            const address = MihomoUI.decodeApiText(row[source ? 'sourceIP' : 'destinationIP']);
            const cell = MihomoUI.element(document, 'span', {}, MihomoUI.decodeApiText(row[column.id]));
            if (isCopyAddressText(address)) {
                const label = (source ? {{ lang._('Copy source IP address') | json_encode }} : {{ lang._('Copy destination IP address') | json_encode }}) + ': ' + address;
                const button = MihomoUI.element(document, 'button', {type: 'button', class: 'btn btn-xs btn-default cmd-copy-address',
                    style: 'margin-left:4px', 'data-address': address, 'aria-label': label, title: label});
                button.appendChild(MihomoUI.element(document, 'i', {class: 'fa fa-copy fa-fw', 'aria-hidden': 'true'}));
                cell.appendChild(button);
            }
            return cell.outerHTML;
        }

        let addressCopyAttempt = 0;
        let connectionCopyButton = null;
        function resetConnectionCopy() {
            $('#connection-copy-state').text('');
            $('#connection-copy-manual').prop('hidden', true);
            $('#connection-copy-value').val('');
        }
        $('#grid-connections').on('click', '.cmd-copy-address', async function (event) {
            event.stopPropagation();
            const address = this.getAttribute('data-address');
            if (!isCopyAddressText(address)) { return; }
            const attempt = ++addressCopyAttempt;
            connectionCopyButton = this;
            resetConnectionCopy();
            const copied = await MihomoUI.copyText(address, navigator.clipboard);
            if (attempt !== addressCopyAttempt) { return; }
            $('#connection-copy-state').text(copied
                ? {{ lang._('IP address copied.') | json_encode }}
                : {{ lang._('Clipboard unavailable. Copy the selected IP address manually.') | json_encode }});
            if (!copied) {
                $('#connection-copy-manual').prop('hidden', false);
                const field = $('#connection-copy-value').val(address)[0];
                field.focus();
                field.select();
            }
        });
        $('#connection-copy-dismiss').on('click', function () {
            ++addressCopyAttempt;
            resetConnectionCopy();
            if (connectionCopyButton && connectionCopyButton.isConnected) { connectionCopyButton.focus(); }
            connectionCopyButton = null;
        });

        /* ------------------------------------------------------------------ *
         * 活动连接表格
         * ------------------------------------------------------------------ */
        let connectionsReady = false;
        $("#grid-connections").on('load.rs.jquery.bootgrid', function () {
            connectionsReady = false;
            $('#connection-visible-count').text('—');
        }).UIBootgrid({
            'search': '/api/mihomo/dashboard/connections',
            'options': {
                'rowSelect': false,
                'multiSelect': false,
                'responseHandler': function (response) {
                    connectionsReady = !!(response && response.ready === true && Array.isArray(response.rows));
                    return response;
                },
                'formatters': {
                    'addressformatter': connectionAddressCell,
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
            $('#connection-visible-count').text(connectionsReady
                ? fmtCount($('#grid-connections').bootgrid('getCurrentRows').length)
                : {{ lang._('Unavailable') | json_encode }});
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
        $('#overview-pause').click(function () {
            const paused = !overviewPoller.paused;
            // Even a brief pause must not average traffic across the missing samples.
            trafficHistory.add(Date.now(), null, null, false);
            if (!paused) { lastMetadata = 0; }
            overviewPoller.setPaused(paused);
            $(this).text(paused ? {{ lang._('Resume statistics') | json_encode }} : {{ lang._('Pause statistics') | json_encode }});
            $('#overview-polling-state').text(paused
                ? {{ lang._('Statistics auto refresh is paused. In-flight reads may finish; actions can still refresh results. Other panels remain live.') | json_encode }}
                : '');
        });
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

<style id="mihomo-compact-style">
    /* Only the opt-in layout overrides the existing inline dimensions. */
    #mihomo-overview.mihomo-compact .mihomo-metrics .content-box {
        padding: 8px 12px !important;
        min-height: 72px !important;
        margin-bottom: 8px !important;
    }
    #mihomo-overview.mihomo-compact #traffic-chart-container { height: 140px !important; }
    #mihomo-overview.mihomo-compact #proxy-groups > .row { display: flex; flex-wrap: wrap; }
    #mihomo-overview.mihomo-compact #proxy-groups > .row::before,
    #mihomo-overview.mihomo-compact #proxy-groups > .row::after { content: none; }
    #mihomo-overview.mihomo-compact #proxy-groups > .row > div {
        width: 100%;
        min-width: 0;
        margin-bottom: 8px !important;
    }
    #mihomo-overview.mihomo-compact #proxy-groups .content-box:has(> ul[data-group]:not([hidden])) { height: 220px !important; }
    #mihomo-overview.mihomo-compact #proxy-groups .content-box > div {
        padding: 6px 10px !important;
        overflow-wrap: anywhere;
    }
    #mihomo-overview.mihomo-compact #proxy-groups .list-group-item { padding: 4px 10px !important; }
    #mihomo-overview.mihomo-compact #proxy-groups button { min-height: 24px; min-width: 24px; }
    @media (min-width: 768px) {
        #mihomo-overview.mihomo-compact .mihomo-metrics > div { width: 25%; }
    }
    @media (min-width: 992px) {
        #mihomo-overview.mihomo-compact #proxy-groups > .row > div { width: 50%; }
    }
    @media (min-width: 1200px) {
        #mihomo-overview.mihomo-compact #proxy-groups > .row > div { width: 33.333333%; }
    }
</style>


<div id="mihomo-overview">
<div class="row">
    <section class="col-xs-12">
        <div class="checkbox">
            <label for="compact-overview" title="{{ lang._('Browser-only layout preference. Turn off to forget it.') }}">
                <input type="checkbox" id="compact-overview" aria-controls="mihomo-overview">
                {{ lang._('Compact overview (experimental)') }}
            </label>
        </div>
        <div id="mihomo-service-state"></div>
        <p id="dashboard-action-state" class="text-danger" role="alert"></p>
        <button type="button" class="btn btn-default btn-sm" id="overview-pause" aria-describedby="overview-polling-state">{{ lang._('Pause statistics') }}</button>
        <p id="overview-polling-state" class="text-muted" role="status" aria-live="polite"></p>
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
    <span id="traffic-totals-note" class="text-muted" role="status">{{ lang._('Core totals') }}</span>
    <button type="button" id="reset-traffic-totals" class="btn btn-xs btn-default" disabled title="{{ lang._('Reset displayed totals from the latest sample. Reloading restores core totals.') }}">{{ lang._('Reset displayed totals') }}</button>
    <button type="button" id="restore-traffic-totals" class="btn btn-xs btn-default" disabled>{{ lang._('Show core totals') }}</button>
    <label for="traffic-totals-bytes" style="font-weight:normal; margin:0;">
        <input type="checkbox" id="traffic-totals-bytes"> {{ lang._('Show totals in bytes') }}
    </label>
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
                    <select id="mode-select" aria-describedby="mode-hint" class="form-control" style="width: auto; display: inline-block; height: 28px; padding: 2px 6px;">
                        <option value="">{{ lang._('…') }}</option>
                        <option value="rule">{{ lang._('Rule-based') }}</option>
                        <option value="global">{{ lang._('Global') }}</option>
                        <option value="direct">{{ lang._('Direct') }}</option>
                    </select>
                </span>
            </div>
            <p id="mode-hint" class="text-muted" role="status" style="padding:0 14px;"></p>
            <div style="padding: 12px;">
                <div id="traffic-chart-container" style="height: 200px;">
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
                <button type="button" id="export-selections" class="btn btn-xs btn-default pull-right">{{ lang._('Export selections (JSON)') }}</button>
            </div>
            <div style="padding:0 12px 12px; display:flex; flex-wrap:wrap; align-items:center; gap:8px;">
                <label for="proxy-node-order" style="font-weight:normal; margin:0;">{{ lang._('Node order') }}</label>
                <select id="proxy-node-order" class="form-control" style="width:auto;" aria-describedby="proxy-node-order-note proxy-node-delay-order-note">
                    <option value="config">{{ lang._('Configuration order') }}</option>
                    <option value="name-asc">{{ lang._('Name (A–Z)') }}</option>
                    <option value="name-desc">{{ lang._('Name (Z–A)') }}</option>
                    <option value="delay-asc">{{ lang._('Last delay: fastest first') }}</option>
                    <option value="delay-desc">{{ lang._('Last delay: slowest first') }}</option>
                </select>
                <span id="proxy-node-order-note" class="text-muted">{{ lang._('Favorites stay first. Name order uses natural numbers and ignores case. Resets on page reload.') }}</span>
                <span id="proxy-node-delay-order-note" class="text-muted">{{ lang._('Uses the last recorded delay, which may be old. Failed and untested nodes sort last within each section. Sorting does not run tests or change selections.') }}</span>
            </div>
            <div style="padding:0 12px;">
                <b>{{ lang._('Proxy latency summary') }}</b>
                <p id="proxy-health-summary" role="status">{{ lang._('Loading …') }}</p>
                <p class="text-muted">{{ lang._('Latest recorded results across all groups, not live availability. The name filter does not change these counts. Groups and built-in actions are excluded.') }}</p>
            </div>
            <p id="selection-export-state" class="text-muted" role="status" style="padding:0 12px;"></p>
            <div id="selection-export-panel" hidden style="padding:0 12px 12px;">
                <label for="selection-export-text">{{ lang._('Group selections (JSON)') }}</label>
                <p id="selection-export-help" class="text-muted">{{ lang._('Includes all reported groups. Automatic selections may change; null means no single selection was reported. Group and node names are included.') }}</p>
                <textarea id="selection-export-text" class="form-control" rows="10" readonly spellcheck="false" aria-describedby="selection-export-help"></textarea>
                <button type="button" id="selection-export-dismiss" class="btn btn-xs btn-default">{{ lang._('Dismiss') }}</button>
            </div>
            <p id="proxy-test-state" class="text-muted" role="status" style="padding:0 12px;"></p>
            <p id="proxy-copy-state" class="text-muted" role="status" style="padding:0 12px;"></p>
            <div id="proxy-copy-fallback" hidden style="padding:0 12px 12px;">
                <label for="proxy-copy-text">{{ lang._('Text to copy') }}</label>
                <textarea id="proxy-copy-text" class="form-control" rows="3" readonly spellcheck="false"></textarea>
                <button id="proxy-copy-dismiss" type="button" class="btn btn-xs btn-default">{{ lang._('Dismiss') }}</button>
            </div>
            <p class="text-muted" style="padding:0 12px;">{{ lang._('Star groups to pin them first, or proxies to pin them first in each group. Favorites are saved in this browser; routing is unchanged.') }}</p>
            <p id="proxy-favorites-state" class="text-muted" role="status" style="padding:0 12px;"></p>
            <div class="form-inline" style="padding:0 12px;">
                <label for="proxy-filter">{{ lang._('Filter proxy names') }}</label>
                <input type="search" id="proxy-filter" class="form-control" aria-controls="proxy-groups" aria-describedby="proxy-filter-help" autocomplete="off" />
                <button type="button" id="proxy-filter-clear" class="btn btn-default">{{ lang._('Clear filter') }}</button>
                <span id="proxy-filter-state" class="text-muted" role="status"></span>
                <p id="proxy-filter-help" class="help-block">{{ lang._('Case-insensitive name substring. Group latency tests still cover all nodes in the group.') }}</p>
            </div>
            <div class="form-inline" style="padding:0 12px;">
                <label><input type="checkbox" id="proxy-show-hidden" aria-controls="proxy-groups" aria-describedby="proxy-hide-help" /> {{ lang._('Show hidden proxies') }}</label>
                <span class="text-muted" role="status">{{ lang._('Names marked hidden') }}: <span id="proxy-hidden-count">0</span></span>
                <button type="button" id="proxy-restore-all" class="btn btn-default" disabled>{{ lang._('Restore all proxies') }}</button>
                <p id="proxy-hide-help" class="help-block">{{ lang._('Hiding changes only this page. Selected entries stay visible when they match the name filter. Routing and group latency tests are unchanged.') }}</p>
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
                <span class="text-muted" role="status">{{ lang._('Visible connections') }}: <span id="connection-visible-count">—</span></span>
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
                            <th data-column-id="host" data-type="string" data-formatter="addressformatter">{{ lang._('Host') }}</th>
                            <th data-column-id="source" data-width="11em" data-type="string" data-formatter="addressformatter">{{ lang._('Source') }}</th>
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
                <p id="connection-copy-state" class="text-muted" role="status"></p>
                <div id="connection-copy-manual" hidden>
                    <label for="connection-copy-value">{{ lang._('IP address to copy') }}</label>
                    <input id="connection-copy-value" type="text" class="form-control" readonly>
                    <button id="connection-copy-dismiss" type="button" class="btn btn-xs btn-default">{{ lang._('Dismiss') }}</button>
                </div>
            </div>
        </div>
    </section>
</div>
</div>
