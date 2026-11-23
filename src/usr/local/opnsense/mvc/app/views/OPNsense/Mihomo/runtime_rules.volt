{# Read-only rule snapshot. Search all rows before paging; no background polling. #}
<script>
    $(document).ready(function () {
        const pageSize = 50;
        let rules = [], page = 0, loaded = false, pending = false;

        function renderRules() {
            const query = $('#runtime-rule-search').val().trim().toLocaleLowerCase();
            const type = $('#runtime-rule-type').val();
            const matches = rules.filter(rule => (!type || rule.type === type)
                && (!query || [rule.type, rule.payload, rule.proxy].some(value => value.toLocaleLowerCase().includes(query))));
            page = Math.min(page, Math.max(0, Math.ceil(matches.length / pageSize) - 1));
            const start = page * pageSize;
            const body = document.getElementById('runtime-rule-rows');
            const rows = matches.slice(start, start + pageSize).map(rule => {
                const row = MihomoUI.element(document, 'tr');
                ['position', 'type', 'payload', 'proxy'].forEach(key => {
                    row.appendChild(MihomoUI.element(document, 'td', {style: 'overflow-wrap:anywhere'}, rule[key]));
                });
                return row;
            });
            if (!rows.length) {
                const row = MihomoUI.element(document, 'tr');
                row.appendChild(MihomoUI.element(document, 'td', {colspan: '4'}, loaded
                    ? {{ lang._('No matching rules.') | json_encode }} : '—'));
                rows.push(row);
            }
            body.replaceChildren(...rows);
            $('#runtime-rule-count').text(loaded ? {{ lang._('Showing %s–%s of %s matches (%s loaded rules).') | json_encode }}
                .replace('%s', matches.length ? start + 1 : 0).replace('%s', Math.min(start + pageSize, matches.length))
                .replace('%s', matches.length).replace('%s', rules.length) : '');
            $('#runtime-rule-prev').prop('disabled', page === 0);
            $('#runtime-rule-next').prop('disabled', start + pageSize >= matches.length);
        }

        function loadRules() {
            if (pending) { return; }
            pending = true;
            $('#runtime-rule-refresh').prop('disabled', true);
            $('#runtime-rule-state').text({{ lang._('Loading …') | json_encode }});
            ajaxGet('/api/mihomo/dashboard/rules', {}, function (data, status) {
                pending = false;
                $('#runtime-rule-refresh').prop('disabled', false);
                if (status !== 'success' || !data || data.ready !== true || !Array.isArray(data.rows)) {
                    $('#runtime-rule-state').text(loaded
                        ? {{ lang._('Runtime rules could not be refreshed. Showing the last successful snapshot.') | json_encode }}
                        : {{ lang._('Runtime rules are unavailable. Check the service and controller, then refresh.') | json_encode }});
                    return;
                }
                rules = data.rows.map(rule => ({position: rule.position, type: MihomoUI.decodeApiText(rule.type),
                    payload: MihomoUI.decodeApiText(rule.payload), proxy: MihomoUI.decodeApiText(rule.proxy)}));
                loaded = true;
                const selectedType = $('#runtime-rule-type').val();
                const types = Array.from(new Set(rules.map(rule => rule.type))).sort();
                const select = document.getElementById('runtime-rule-type');
                select.replaceChildren(MihomoUI.element(document, 'option', {value: ''}, {{ lang._('All rule types') | json_encode }}),
                    ...types.map(type => MihomoUI.element(document, 'option', {value: type}, type)));
                $('#runtime-rule-type').val(types.includes(selectedType) ? selectedType : '');
                $('#runtime-rule-state').text({{ lang._('Snapshot loaded. Refresh to read the current runtime rules.') | json_encode }});
                renderRules();
            });
        }

        $('#runtime-rule-search').on('input', function () { page = 0; renderRules(); });
        $('#runtime-rule-type').on('change', function () { page = 0; renderRules(); });
        $('#runtime-rule-clear').on('click', function () {
            $('#runtime-rule-search').val(''); $('#runtime-rule-type').val(''); page = 0; renderRules();
        });
        $('#runtime-rule-prev').on('click', function () { page = Math.max(0, page - 1); renderRules(); });
        $('#runtime-rule-next').on('click', function () { page++; renderRules(); });
        $('#runtime-rule-refresh').on('click', loadRules);
        $('a[href="#routing-rules"]').on('shown.bs.tab', function () { if (!loaded) { loadRules(); } });
        renderRules();
    });
</script>
<div class="content-box" style="padding:12px;">
    <p class="text-muted">{{ lang._('Search the loaded top-level Mihomo rules by type, value or proxy target. Position preserves controller order. This is a text search, not a routing simulation; rule-set contents are not expanded.') }}</p>
    <div style="display:flex; flex-wrap:wrap; align-items:center; gap:8px; margin-bottom:12px;">
        <label for="runtime-rule-search">{{ lang._('Search runtime rules') }}</label>
        <input id="runtime-rule-search" type="search" class="form-control" style="width:auto; flex:1 1 200px;" aria-controls="runtime-rule-table">
        <label for="runtime-rule-type">{{ lang._('Rule type') }}</label>
        <select id="runtime-rule-type" class="form-control" style="width:auto;" aria-controls="runtime-rule-table">
            <option value="">{{ lang._('All rule types') }}</option>
        </select>
        <button id="runtime-rule-clear" type="button" class="btn btn-default">{{ lang._('Clear filters') }}</button>
        <button id="runtime-rule-refresh" type="button" class="btn btn-default">{{ lang._('Refresh') }}</button>
    </div>
    <p id="runtime-rule-state" role="status"></p>
    <p id="runtime-rule-count" class="text-muted" role="status"></p>
    <div class="table-responsive">
        <table id="runtime-rule-table" class="table table-condensed table-hover table-striped">
            <thead><tr>
                <th scope="col">{{ lang._('Position') }}</th><th scope="col">{{ lang._('Rule type') }}</th>
                <th scope="col">{{ lang._('Rule value') }}</th><th scope="col">{{ lang._('Proxy target') }}</th>
            </tr></thead>
            <tbody id="runtime-rule-rows"></tbody>
        </table>
    </div>
    <button id="runtime-rule-prev" type="button" class="btn btn-default" disabled>{{ lang._('Previous') }}</button>
    <button id="runtime-rule-next" type="button" class="btn btn-default" disabled>{{ lang._('Next') }}</button>
</div>
