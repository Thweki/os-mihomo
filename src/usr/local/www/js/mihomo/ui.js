/* Native WebGUI helpers. No controller addresses, credentials or network calls. */
(function (root, factory) {
    'use strict';
    const api = factory();
    if (typeof module === 'object' && module.exports) { module.exports = api; }
    else { root.MihomoUI = api; }
}(typeof window === 'undefined' ? globalThis : window, function () {
    'use strict';
    function formatBytes(value, locale) {
        const number = Number(value);
        if (!Number.isFinite(number) || number < 0) { return '—'; }
        const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
        let index = 0, scaled = number;
        while (scaled >= 1024 && index < units.length - 1) { scaled /= 1024; index++; }
        return scaled.toLocaleString(locale || undefined, {minimumFractionDigits: 1, maximumFractionDigits: 1}) + ' ' + units[index];
    }
    function formatTrafficTotal(value, rawBytes, locale) {
        // Counters are whole bytes. Do not present missing or imprecise data as exact totals.
        if (!Number.isSafeInteger(value) || value < 0) { return '—'; }
        return rawBytes ? value.toLocaleString(locale || undefined, {maximumFractionDigits: 0}) + ' B'
            : formatBytes(value, locale);
    }
    // Total hours (not a clock time) remain unbounded across multiple days.
    function formatUptime(seconds) {
        if (!Number.isSafeInteger(seconds) || seconds < 0) { return null; }
        return [Math.floor(seconds / 3600), Math.floor(seconds / 60) % 60, seconds % 60]
            .map(value => String(value).padStart(2, '0')).join(':');
    }
    // Internal OPNsense API responses use htmlspecialchars(..., ENT_NOQUOTES).
    // Decode exactly one layer, preserving entities that are literal file data.
    function decodeApiText(value) {
        return String(value == null ? '' : value).replace(/&(amp|lt|gt);/g, function (entity) {
            return {'&amp;': '&', '&lt;': '<', '&gt;': '>'}[entity];
        });
    }
    // Copy the observed match conditions, not a reconstructed executable PF rule.
    // Report only selection metadata, never the full controller response.
    function exportSelections(groups, capturedAt) {
        return JSON.stringify({capturedAt, groups: groups.map(group => ({
            group: decodeApiText(group.name),
            type: decodeApiText(group.type),
            selected: typeof group.now === 'string' && group.now !== '' ? decodeApiText(group.now) : null
        }))}, null, 2);
    }
    function ruleMatchText(rule) {
        if (!rule || typeof rule.source !== 'string' || !rule.source.trim()
            || typeof rule.destination !== 'string' || !rule.destination.trim()) { return ''; }
        return 'from ' + decodeApiText(rule.source) + ' to ' + decodeApiText(rule.destination);
    }
    // Clipboard permission/security failures leave the caller a manual-copy path.
    async function copyText(text, clipboard) {
        try {
            if (!clipboard || typeof clipboard.writeText !== 'function') { return false; }
            await clipboard.writeText(text);
            return true;
        } catch (error) { return false; }
    }
    // Mihomo's logrus text headers: file output and (optionally colored) console
    // output. Anchor at the header so severity words inside messages never match.
    // Strip ANSI styling only for classification; keep the displayed line intact.
    function logLevel(line) {
        const plain = line.replace(/\x1b\[[0-9;]*m/g, '');
        const field = plain.match(/^(?:time=(?:"[^"\r\n]*"|[^\s"]+)\s+)?level=(debug|info|warn|warning|error|fatal|panic)(?=\s|$)/i);
        if (field) { return field[1].toLowerCase().replace(/^warn$/, 'warning'); }
        const consoleLevel = plain.match(/^(DEBU|INFO|WARN|ERRO|FATA|PANI)\[[^\]\r\n]*\](?=\s|$)/i);
        if (consoleLevel) {
            return {DEBU: 'debug', INFO: 'info', WARN: 'warning', ERRO: 'error', FATA: 'fatal', PANI: 'panic'}[consoleLevel[1].toUpperCase()];
        }
        return 'unknown';
    }
    // Merge context windows by position, preserving repeated/blank log lines.
    // Search only the already loaded, redacted text; never interpret it as regex/HTML.
    function filterLogLines(lines, query, context, eligible = () => true) {
        const needle = query.toLocaleLowerCase();
        const allowed = lines.map(eligible);
        if (!needle) {
            const visible = lines.filter((_, index) => allowed[index]);
            return {lines: visible, matches: visible.length};
        }
        const radius = context === 2 || context === 5 ? context : 0;
        const ranges = [];
        let matches = 0;
        lines.forEach((line, index) => {
            if (!allowed[index] || !line.toLocaleLowerCase().includes(needle)) { return; }
            matches++;
            const start = Math.max(0, index - radius), end = Math.min(lines.length, index + radius + 1);
            const previous = ranges[ranges.length - 1];
            if (previous && start <= previous.end) { previous.end = end; }
            else { ranges.push({start, end}); }
        });
        return {lines: ranges.flatMap(range => lines.slice(range.start, range.end).filter((_, offset) => allowed[range.start + offset])), matches};
    }
    // Page-local measurement; raw counters still feed the rate/history calculation.
    class TrafficTotals {
        constructor() {
            this.current = null;
            this.previous = null;
            this.baseline = null;
            this.restarted = false;
        }
        update(download, upload, ready) {
            if (!ready || !Number.isSafeInteger(download) || download < 0 || !Number.isSafeInteger(upload) || upload < 0) {
                this.current = null;
                return;
            }
            // Keep the last valid sample across failures to detect a counter reset.
            if (this.baseline && this.previous && (download < this.previous.download || upload < this.previous.upload)) {
                this.baseline = null;
                this.restarted = true;
            }
            this.current = {download, upload};
            this.previous = this.current;
        }
        reset() {
            if (!this.current) { return false; }
            this.baseline = this.current;
            this.restarted = false;
            return true;
        }
        restore() {
            this.baseline = null;
            this.restarted = false;
        }
        values() {
            if (!this.current) { return null; }
            const base = this.baseline || {download: 0, upload: 0};
            return {download: this.current.download - base.download, upload: this.current.upload - base.upload};
        }
    }
    // Summarize only the projection supplied by the current successful poll.
    function summarizeProxyLatency(groups) {
        if (!Array.isArray(groups) || groups.some(group =>
            !group || typeof group.name !== 'string' || !Array.isArray(group.members))) {
            return null;
        }
        const groupNames = new Set(groups.map(group => group.name));
        const actions = new Set(['direct', 'reject', 'rejectdrop', 'pass']);
        const groupTypes = new Set(['selector', 'urltest', 'fallback', 'loadbalance', 'relay']);
        const seen = new Set();
        const totals = {responding: 0, noPositive: 0, unknown: 0};
        for (const group of groups) {
            for (const member of group.members) {
                if (!member || typeof member.name !== 'string' || !member.name ||
                    typeof member.type !== 'string') {
                    return null;
                }
                const type = member.type.toLowerCase();
                if (groupNames.has(member.name) || groupTypes.has(type) ||
                    actions.has(type) || seen.has(member.name)) { continue; }
                seen.add(member.name);
                if (!member.type || !Number.isSafeInteger(member.delay)) { totals.unknown++; }
                else if (member.delay > 0) { totals.responding++; }
                else { totals.noPositive++; }
            }
        }
        return totals;
    }
    function comparisonReport(data, collectedAt) {
        if (!data || data.status !== 'ok' || !Array.isArray(data.rows)) { return null; }
        return {
            schema_version: 1,
            collected_at: collectedAt,
            runtime_available: data.runtime === true,
            rows: data.rows.map(row => {
                const secret = row.secret === true || row.key === 'secret';
                // Select fields explicitly; never serialize the whole API response.
                return {
                    key: decodeApiText(row.key), label: decodeApiText(row.label),
                    group: decodeApiText(row.group), state: row.state,
                    managed: typeof row.managed === 'boolean' ? row.managed : null,
                    runtime_only: row.runtime_only === true, secret,
                    model: secret ? null : decodeApiText(row.model),
                    file: secret ? null : decodeApiText(row.file),
                    runtime: secret ? null : decodeApiText(row.runtime)
                };
            })
        };
    }
    // Browser-local, per-origin selections only; never retain controller metadata.
    class ProxySnapshots {
        constructor(storage) { this.storage = storage; this.key = 'mihomo.proxySnapshots.v1'; }
        read() {
            const raw = this.storage.getItem(this.key);
            if (raw === null) { return []; }
            const data = JSON.parse(raw);
            const text = value => typeof value === 'string' && value.length > 0;
            if (!data || data.version !== 1 || !Array.isArray(data.snapshots) || data.snapshots.length > 20
                || data.snapshots.some(item => !item || !text(item.name) || item.name.length > 80
                    || !Array.isArray(item.selections) || !item.selections.length
                    || item.selections.some(pair => !pair || !text(pair.group) || !text(pair.member))
                    || new Set(item.selections.map(pair => pair.group)).size !== item.selections.length)
                || new Set(data.snapshots.map(item => item.name)).size !== data.snapshots.length) {
                throw new Error('storage');
            }
            return data.snapshots.map(item => ({name: item.name,
                selections: item.selections.map(pair => ({group: pair.group, member: pair.member}))}));
        }
        save(name, groups) {
            name = name.trim();
            if (!name || name.length > 80) { throw new Error('name'); }
            const snapshots = this.read();
            if (snapshots.some(item => item.name === name)) { throw new Error('duplicate'); }
            if (snapshots.length >= 20) { throw new Error('limit'); }
            const selections = snapshotGroups(groups).filter(group => group.type === 'Selector').map(group => {
                if (!group.now || !group.members.includes(group.now)) { throw new Error('groups'); }
                return {group: group.name, member: group.now};
            });
            if (!selections.length) { throw new Error('empty'); }
            snapshots.push({name, selections});
            this.storage.setItem(this.key, JSON.stringify({version: 1, snapshots}));
            return name;
        }
        remove(name) {
            const snapshots = this.read().filter(item => item.name !== name);
            this.storage.setItem(this.key, JSON.stringify({version: 1, snapshots}));
        }
    }
    function snapshotGroups(groups) {
        if (!Array.isArray(groups)) { throw new Error('groups'); }
        const result = groups.map(group => {
            if (!group || typeof group.name !== 'string' || !group.name || typeof group.type !== 'string'
                || typeof group.now !== 'string' || !Array.isArray(group.members)
                || group.members.some(member => !member || typeof member.name !== 'string' || !member.name)) {
                throw new Error('groups');
            }
            return {name: decodeApiText(group.name), type: group.type, now: decodeApiText(group.now),
                members: group.members.map(member => decodeApiText(member.name))};
        });
        if (new Set(result.map(group => group.name)).size !== result.length) { throw new Error('groups'); }
        return result;
    }
    function planProxySnapshot(snapshot, groups) {
        const current = new Map(snapshotGroups(groups).map(group => [group.name, group]));
        const changes = [], missing = [];
        snapshot.selections.forEach(pair => {
            const group = current.get(pair.group);
            if (!group || group.type !== 'Selector' || !group.members.includes(pair.member)) { missing.push(pair.group); }
            else if (group.now !== pair.member) { changes.push({group: pair.group, member: pair.member, previous: group.now}); }
        });
        return {changes, missing};
    }
    class TrafficHistory {
        constructor(saved) {
            this.samples = [];
            this.previous = null;
            if (Array.isArray(saved)) {
                this.samples = saved.filter(p => p && Number.isFinite(p.time) && p.time <= Date.now()
                    && (p.down === null || Number.isFinite(p.down) && p.down >= 0)
                    && (p.up === null || Number.isFinite(p.up) && p.up >= 0)).slice(-1800);
            }
        }
        add(time, download, upload, ready) {
            const current = {time, download, upload};
            let down = null, up = null;
            const previous = this.previous;
            if (ready && Number.isFinite(download) && Number.isFinite(upload)) {
                const elapsed = previous ? (time - previous.time) / 1000 : 0;
                if (previous && elapsed >= 0.5 && elapsed <= 10 && download >= previous.download && upload >= previous.upload) {
                    down = (download - previous.download) / elapsed;
                    up = (upload - previous.upload) / elapsed;
                }
                this.previous = current;
            } else { this.previous = null; }
            this.samples.push({time, down, up});
            this.samples = this.samples.filter(p => p.time >= time - 3600000).slice(-1800);
            return {down, up};
        }
        window(seconds, now) {
            // Keep a bounded number of chart points; null samples retain gaps.
            const points = this.samples.filter(p => p.time >= now - seconds * 1000 && p.time <= now);
            const stride = Math.max(1, Math.ceil(points.length / 300));
            const result = [];
            for (let i = 0; i < points.length; i += stride) {
                const bucket = points.slice(i, i + stride);
                const valid = bucket.every(p => p.down !== null && p.up !== null);
                result.push({time: bucket[bucket.length - 1].time,
                    down: valid ? bucket.reduce((sum, p) => sum + p.down, 0) / bucket.length : null,
                    up: valid ? bucket.reduce((sum, p) => sum + p.up, 0) / bucket.length : null});
            }
            return result;
        }
    }
    // A request finishes before its next timer starts. Hidden pages never enqueue work.
    class Poller {
        constructor(request, interval, options) {
            this.request = request;
            this.interval = interval;
            this.options = options || {};
            this.hidden = this.options.hidden || (() => document.hidden);
            this.schedule = this.options.schedule || ((callback, delay) => setTimeout(callback, delay));
            this.cancel = this.options.cancel || (timer => clearTimeout(timer));
            this.timer = null;
            this.pending = false;
            this.failures = 0;
            this.stopped = false;
            this.paused = false;
        }
        refresh() {
            this.cancel(this.timer);
            if (this.stopped || this.hidden() || this.pending) { return; }
            this.pending = true;
            let completed = false;
            this.request(ok => {
                if (completed) { return; }
                completed = true;
                this.pending = false;
                this.failures = ok ? 0 : Math.min(this.failures + 1, 5);
                if (!this.stopped && !this.paused && !this.hidden()) {
                    this.timer = this.schedule(() => {
                        if (!this.paused) { this.refresh(); }
                    }, Math.min(this.interval * Math.pow(2, this.failures), 60000));
                }
            });
        }
        // Pause automatic reads only; explicit refreshes may still show action results.
        setPaused(paused) {
            if (this.stopped || this.paused === paused) { return; }
            this.paused = paused;
            this.cancel(this.timer);
            if (!paused) { this.failures = 0; this.refresh(); }
        }
        visibilityChanged() {
            if (this.paused) { this.cancel(this.timer); }
            else { this.refresh(); }
        }
        stop() { this.stopped = true; this.cancel(this.timer); }
    }
    function runLimited(items, limit, worker, progress, done, shouldContinue) {
        let next = 0, active = 0, completed = 0, failed = 0;
        let cancelled = false, finished = false;
        const state = () => ({completed, total: items.length, failed, cancelled, skipped: cancelled ? items.length - next : 0});
        function pump() {
            if (finished) { return; }
            if (!cancelled && shouldContinue && !shouldContinue()) {
                cancelled = true;
                progress(state());
            }
            if (active === 0 && (cancelled || completed === items.length)) {
                finished = true; done(state()); return;
            }
            while (!cancelled && !finished && active < limit && next < items.length) {
                const item = items[next++]; active++;
                let settled = false;
                worker(item, ok => {
                    if (settled) { return; }
                    settled = true; active--; completed++; if (!ok) { failed++; }
                    progress(state());
                    pump();
                });
            }
        }
        pump();
        return {cancel() {
            if (finished || cancelled) { return; }
            // Requests already sent may still update core latency history. Drain
            // them before completing so a new batch cannot overlap this one.
            cancelled = true;
            progress(state());
            pump();
        }};
    }
    // Probe concrete members once, excluding nested groups and built-in actions.
    function automaticTestNames(groups) {
        const groupNames = new Set(groups.map(group => decodeApiText(group.name)));
        const names = new Set();
        groups.forEach(group => (group.members || []).forEach(member => {
            const name = decodeApiText(member.name);
            const type = String(member.type || '').toLowerCase().replace(/[-_ ]/g, '');
            if (name && type && !groupNames.has(name)
                && !/^(direct|reject|rejectdrop|pass|compatible|dns|selector|urltest|fallback|loadbalance|relay)$/.test(type)) {
                names.add(name);
            }
        }));
        return Array.from(names);
    }
    // Only this test run's successful measurements can nominate a proxy.
    function fastestProxy(group, delays) {
        if (!group || group.type !== 'Selector') { return null; }
        const excluded = new Set(['direct', 'reject', 'rejectdrop', 'pass', 'compatible', 'selector', 'urltest', 'fallback', 'loadbalance', 'relay']);
        let best = null, bestDelay = Infinity;
        (group.members || []).forEach(member => {
            const name = decodeApiText(member.name), delay = delays.get(name);
            if (excluded.has(String(member.type).toLowerCase().replace(/[-_]/g, ''))
                || ['DIRECT', 'REJECT', 'REJECT-DROP', 'PASS', 'COMPATIBLE'].includes(name)
                || !Number.isFinite(delay) || delay <= 0) { return; }
            if (delay < bestDelay || delay === bestDelay && member.selected) {
                best = member; bestDelay = delay;
            }
        });
        return best && !best.selected ? decodeApiText(best.name) : null;
    }
    function proxyGroupSignature(group) {
        return group && JSON.stringify([group.name, group.type,
            (group.members || []).map(member => [member.name, member.type, !!member.selected])]);
    }
    // Browser-local display preferences; names are decoded once at the API boundary.
    class ProxyFavorites {
        constructor(storage) {
            this.storage = storage || (() => localStorage);
            this.groups = new Set();
            this.proxies = new Set();
            try {
                const saved = JSON.parse(this.storage().getItem('mihomo.favorites.v1'));
                for (const kind of ['groups', 'proxies']) {
                    if (saved && Array.isArray(saved[kind])) {
                        this[kind] = new Set(saved[kind].filter(name => typeof name === 'string'));
                    }
                }
            } catch (error) { /* Invalid or unavailable storage starts with no favorites. */ }
        }
        has(kind, name) { return this[kind].has(name); }
        toggle(kind, name) {
            if (this.has(kind, name)) { this[kind].delete(name); }
            else { this[kind].add(name); }
            try {
                this.storage().setItem('mihomo.favorites.v1', JSON.stringify({groups: [...this.groups], proxies: [...this.proxies]}));
                return true;
            } catch (error) { return false; } // Keep the in-memory choice for this visit.
        }
        order(items, kind) {
            // Stable partition leaves controller order intact within each section.
            const starred = [], rest = [];
            items.forEach(item => (this.has(kind, decodeApiText(item.name)) ? starred : rest).push(item));
            return starred.concat(rest);
        }
    }
    // Notes use exact decoded names, including names shared by multiple groups.
    class ProxyNotes {
        constructor(storage) {
            this.storage = storage || (() => localStorage);
            this.notes = new Map();
            try {
                const saved = JSON.parse(this.storage().getItem('mihomo.proxy-notes.v1'));
                if (Array.isArray(saved)) {
                    saved.forEach(entry => {
                        if (Array.isArray(entry) && entry.length === 2 && typeof entry[0] === 'string'
                            && typeof entry[1] === 'string' && entry[1].trim() && entry[1].length <= 160) {
                            this.notes.set(entry[0], entry[1]);
                        }
                    });
                }
            } catch (error) { /* Invalid or unavailable storage starts with no notes. */ }
        }
        get(name) { return this.notes.get(name) || ''; }
        set(name, text) {
            if (typeof name !== 'string' || typeof text !== 'string' || text.length > 160) { return 'invalid'; }
            text = text.trim();
            if (text) { this.notes.set(name, text); }
            else { this.notes.delete(name); }
            try {
                this.storage().setItem('mihomo.proxy-notes.v1', JSON.stringify([...this.notes]));
                return 'saved';
            } catch (error) { return 'temporary'; } // Keep edits for this visit, including removals.
        }
    }
    // Every dynamic value reaches textContent/setAttribute, never HTML parsing.
    function element(doc, tag, attrs, text) {
        const node = doc.createElement(tag);
        Object.keys(attrs || {}).forEach(key => node.setAttribute(key, String(attrs[key])));
        if (text !== undefined) { node.textContent = String(text); }
        return node;
    }
    // A warning needs evidence: untested/missing results are possible exits, not failures.
    // Propagate those exits backwards through the group graph, without recursion.
    function emptyProxyGroups(groups) {
        const byName = new Map(groups.map(group => [decodeApiText(group.name), group]));
        const parents = new Map(), possible = new Set(), queue = [];
        function mark(name) {
            if (!possible.has(name)) { possible.add(name); queue.push(name); }
        }
        byName.forEach((group, name) => {
            if (!Array.isArray(group.members)) { mark(name); return; }
            group.members.forEach(member => {
                const target = decodeApiText(member.name);
                if (byName.has(target)) {
                    if (!parents.has(target)) { parents.set(target, []); }
                    parents.get(target).push(name);
                    return;
                }
                const type = decodeApiText(member.type).toLowerCase();
                if (type === 'reject' || type === 'rejectdrop') { return; }
                if (!type || ['direct', 'pass', 'passrule', 'rematch', 'dns', 'compatible', 'unknown',
                    'selector', 'urltest', 'fallback', 'loadbalance', 'relay'].includes(type)
                    || typeof member.delay !== 'number' || !Number.isFinite(member.delay) || member.delay > 0) {
                    mark(name);
                }
            });
        });
        for (let i = 0; i < queue.length; i++) {
            (parents.get(queue[i]) || []).forEach(mark);
        }
        return new Set(Array.from(byName.keys()).filter(name => !possible.has(name)));
    }
    function latencySparkline(doc, history, label, delayText) {
        const samples = Array.isArray(history) ? history.slice(-10).map(value =>
            typeof value === 'number' && Number.isFinite(value) ? value : null) : [];
        const description = label + ': ' + (samples.length ? samples.map(delayText).join(' → ') : delayText(null));
        const wrapper = element(doc, 'span', {title: description, style: 'display:inline-flex;flex:0 0 80px'});
        const svg = (tag, attrs) => {
            const node = doc.createElementNS('http://www.w3.org/2000/svg', tag);
            Object.keys(attrs).forEach(key => node.setAttribute(key, String(attrs[key])));
            return node;
        };
        const chart = svg('svg', {width: 80, height: 24, viewBox: '0 0 80 24', role: 'img', 'aria-label': description});
        const maximum = Math.max(1, ...samples.filter(value => value > 0));
        let points = [];
        const flush = () => {
            if (points.length > 1) { chart.appendChild(svg('polyline', {points: points.join(' '), fill: 'none', stroke: 'currentColor', 'stroke-width': 1.5})); }
            points = [];
        };
        samples.forEach((value, index) => {
            const x = 4 + index * 8;
            if (value === null || value <= 0) {
                flush();
                // Crosses distinguish failed tests from fast responses; unknown samples are gaps.
                if (value !== null) { chart.appendChild(svg('path', {d: 'M' + (x - 2) + ' 18l4 4m0 -4l-4 4', fill: 'none', stroke: 'currentColor', 'stroke-width': 1.5})); }
                return;
            }
            const y = 20 - value / maximum * 16;
            points.push(x + ',' + y);
            chart.appendChild(svg('circle', {cx: x, cy: y, r: 1.5, fill: 'currentColor'}));
        });
        flush();
        if (!samples.length || samples.every(value => value === null)) {
            chart.appendChild(svg('path', {d: 'M36 12h8', stroke: 'currentColor'}));
        }
        wrapper.appendChild(chart);
        return wrapper;
    }
    function normalizeProxyQuery(query) {
        return query.trim().toLowerCase();
    }
    function filterProxyGroups(groups, query) {
        const needle = normalizeProxyQuery(query);
        let total = 0, matched = 0;
        const visible = [];
        groups.forEach(group => {
            const members = group.members || [];
            const matches = needle ? members.filter(member => decodeApiText(member.name).toLowerCase().includes(needle)) : members;
            total += members.length;
            matched += matches.length;
            if (!needle || matches.length) { visible.push(needle ? {...group, members: matches} : group); }
        });
        return {groups: visible, matched, total};
    }
    function orderProxyMembers(members, favorites, direction, collator, delayDirection = 0) {
        if (collator) {
            // Sort decoded display names on a copy; stable ties keep controller order.
            members = members.map(member => ({member, name: decodeApiText(member.name)}))
                .sort((a, b) => direction * collator.compare(a.name, b.name)).map(item => item.member);
        } else if (delayDirection) {
            // The existing controller supplies the last delay as a number or null.
            members = members.slice().sort((a, b) => {
                const aValid = Number.isFinite(a.delay) && a.delay > 0;
                const bValid = Number.isFinite(b.delay) && b.delay > 0;
                if (aValid !== bValid) { return aValid ? -1 : 1; }
                return aValid ? delayDirection * (a.delay - b.delay) : 0;
            });
        }
        // The stable favorite partition preserves display order within both sections.
        return favorites ? favorites.order(members, 'proxies') : members;
    }
    function proxyOrder(nodeOrder) {
        const direction = nodeOrder === 'name-asc' ? 1 : nodeOrder === 'name-desc' ? -1 : 0;
        return [direction, direction ? new Intl.Collator(undefined, {numeric: true, sensitivity: 'base'}) : null];
    }
    function fullProxyGroupTestNames(groups, name, favorites, nodeOrder) {
        const group = groups.find(group => decodeApiText(group.name) === name);
        const members = group ? (group.members || []) : [];
        // A latency display sort must not reorder the existing manual probe queue.
        return [...new Set(orderProxyMembers(members, favorites, ...proxyOrder(nodeOrder))
            .map(member => decodeApiText(member.name)))];
    }
    function renderProxyGroups(container, groups, labels, delayText, delayClass, favorites, nodeOrder = 'config', collapsedGroups, visibility, notes) {
        const doc = container.ownerDocument, el = (tag, attrs, text) => element(doc, tag, attrs, text);
        const [direction, collator] = proxyOrder(nodeOrder);
        const delayDirection = nodeOrder === 'delay-asc' ? 1 : nodeOrder === 'delay-desc' ? -1 : 0;
        function favoriteButton(kind, name, group) {
            const starred = favorites.has(kind, name);
            const label = kind === 'groups' ? labels.favoriteGroup : labels.favoriteProxy;
            const button = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-favorite',
                'data-kind': kind, 'data-name': name, 'aria-pressed': starred ? 'true' : 'false',
                'data-focus-key': JSON.stringify(['favorite', kind, group, name]), 'aria-label': label + ': ' + name, title: label});
            button.appendChild(el('i', {class: 'fa ' + (starred ? 'fa-star text-warning' : 'fa-star-o') + ' fa-fw', 'aria-hidden': 'true'}));
            return button;
        }
        const scroll = new Map();
        container.querySelectorAll('ul[data-group]').forEach(node => scroll.set(node.getAttribute('data-group'), node.scrollTop));
        const active = doc.activeElement;
        const focusKey = active && container.contains(active) ? active.getAttribute('data-focus-key') : null;
        const row = el('div', {class: 'row'});
        const emptyGroups = emptyProxyGroups(groups);
        (favorites ? favorites.order(groups, 'groups') : groups).forEach((group, index) => {
            const name = decodeApiText(group.name);
            const members = group.members || [];
            const collapsed = collapsedGroups && collapsedGroups.has(name);
            const listId = 'mihomo-group-members-' + index;
            const column = el('div', {class: 'col-md-6', style: 'margin-bottom:15px'});
            const card = el('div', {class: 'content-box', style: 'height:' + (collapsed ? 'auto' : '300px') + ';margin-bottom:0;display:flex;flex-direction:column'});
            const header = el('div', {style: 'padding:10px 12px;flex:0 0 auto'});
            if (favorites) { header.appendChild(favoriteButton('groups', name, name)); }
            header.appendChild(el('b', {}, name + ' '));
            header.appendChild(el('span', {class: 'label label-opnsense label-opnsense-sm label-info'}, decodeApiText(group.type)));
            header.appendChild(el('span', {class: 'label label-opnsense label-opnsense-sm label-default',
                style: 'margin-left:6px', 'data-member-count': members.length}, labels.memberCount.replace('%s', members.length)));
            if (emptyGroups.has(name)) {
                header.appendChild(el('span', {class: 'label label-opnsense label-opnsense-sm label-warning',
                    style: 'margin-left:6px;white-space:normal', 'data-empty-group': name,
                    title: labels.emptyGroupHint}, labels.emptyGroup));
            }
            if (collapsedGroups) {
                const label = collapsed ? labels.expandGroup : labels.collapseGroup;
                const toggle = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-collapse-group',
                    style: 'margin-left:6px', 'data-group': name, 'aria-expanded': collapsed ? 'false' : 'true',
                    'aria-controls': listId, 'aria-label': label + ': ' + name, title: label,
                    'data-focus-key': JSON.stringify(['collapse', name])});
                toggle.appendChild(el('i', {class: 'fa fa-chevron-' + (collapsed ? 'right' : 'down') + ' fa-fw', 'aria-hidden': 'true'}));
                header.appendChild(toggle);
            }
            const test = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-test-group pull-right',
                'data-group': name, 'data-focus-key': JSON.stringify(['group', name]), 'aria-label': labels.testGroup + ': ' + name, title: labels.testGroup});
            test.appendChild(el('i', {class: 'fa fa-tachometer fa-fw', 'aria-hidden': 'true'}));
            header.appendChild(test);
            const current = decodeApiText(group.now);
            const copySelection = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-copy pull-right',
                'data-copy-text': JSON.stringify(name) + ': ' + JSON.stringify(current) + '\n',
                'data-focus-key': JSON.stringify(['copy-selection', name]),
                'aria-label': labels.copySelection + ': ' + name, title: labels.copySelection});
            copySelection.disabled = !current;
            copySelection.appendChild(el('i', {class: 'fa fa-copy fa-fw', 'aria-hidden': 'true'}));
            header.appendChild(copySelection);
            if (group.canReset === true) {
                const reset = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-reset-group pull-right',
                    'data-group': name, 'data-focus-key': JSON.stringify(['reset', name]),
                    'aria-label': labels.resetGroup + ': ' + name, title: labels.resetGroup}, labels.resetGroup);
                header.appendChild(reset);
            }
            const list = el('ul', {id: listId, class: 'list-group', 'data-group': name, 'aria-label': name,
                style: 'margin-bottom:0;flex:1 1 auto;overflow-y:auto'});
            // Collapsing changes only presentation; tests use the full group snapshot.
            if (collapsed) { list.setAttribute('hidden', ''); }
            orderProxyMembers(members, favorites, direction, collator, delayDirection).forEach(member => {
                const memberName = decodeApiText(member.name);
                const hidden = visibility && visibility.hiddenNames.has(memberName);
                if (hidden && !visibility.showHidden && !member.selected) { return; }
                const item = el('li', {class: 'list-group-item' + (member.selected ? ' active' : ''),
                    style: 'padding:8px 12px;display:flex;align-items:center;gap:6px', 'data-group': name, 'data-member': memberName});
                if (favorites) { item.appendChild(favoriteButton('proxies', memberName, name)); }
                // Separate buttons avoid nested controls; native buttons support Enter and Space.
                const select = el('button', {type: 'button', class: 'btn btn-link cmd-select',
                    style: 'color:inherit;white-space:normal;text-align:left;padding:0;flex:1;min-width:0;overflow-wrap:anywhere',
                    'aria-pressed': member.selected ? 'true' : 'false', 'data-focus-key': JSON.stringify(['select', name, memberName])});
                select.appendChild(el('i', {class: member.selected ? 'fa fa-check-circle fa-fw text-success' : 'fa fa-circle-o fa-fw text-muted', 'aria-hidden': 'true'}));
                select.appendChild(el('span', {}, ' ' + memberName + ' '));
                select.appendChild(el('small', {class: 'text-muted'}, decodeApiText(member.type)));
                item.appendChild(select);
                item.appendChild(latencySparkline(doc, member.delay_history, labels.latencyHistory, delayText));
                if (notes) {
                    const note = notes.get(memberName);
                    if (note) {
                        select.appendChild(el('small', {'data-proxy-note': memberName,
                            style: 'display:block;white-space:pre-wrap;overflow-wrap:anywhere'}, note));
                    }
                    const edit = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-proxy-note',
                        'data-name': memberName, 'data-focus-key': JSON.stringify(['note', name, memberName]),
                        'aria-label': labels.editNote + ': ' + memberName, title: labels.editNote});
                    edit.appendChild(el('i', {class: 'fa fa-pencil fa-fw', 'aria-hidden': 'true'}));
                    item.appendChild(edit);
                }
                item.appendChild(el('span', {class: 'label label-opnsense label-opnsense-sm ' + delayClass(member.delay)}, delayText(member.delay)));
                const testMember = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-test', 'data-name': memberName,
                    'data-focus-key': JSON.stringify(['test', name, memberName]), 'aria-label': labels.testNode + ': ' + memberName, title: labels.testNode});
                testMember.appendChild(el('i', {class: 'fa fa-bolt fa-fw', 'aria-hidden': 'true'}));
                item.appendChild(testMember);
                const copyName = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-copy',
                    'data-copy-text': memberName, 'data-focus-key': JSON.stringify(['copy-name', name, memberName]),
                    'aria-label': labels.copyName + ': ' + memberName, title: labels.copyName});
                copyName.appendChild(el('i', {class: 'fa fa-copy fa-fw', 'aria-hidden': 'true'}));
                item.appendChild(copyName);
                if (visibility && (!member.selected || hidden)) {
                    const label = hidden ? labels.restoreProxy : labels.hideProxy;
                    const toggle = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-hide-proxy',
                        'data-name': memberName, 'data-group': name, 'data-focus-key': JSON.stringify(['visibility', name, memberName]),
                        'aria-label': label + ': ' + memberName, title: label});
                    toggle.appendChild(el('i', {class: 'fa ' + (hidden ? 'fa-eye' : 'fa-eye-slash') + ' fa-fw', 'aria-hidden': 'true'}));
                    item.appendChild(toggle);
                }
                list.appendChild(item);
            });
            if (visibility && members.length && !list.children.length) {
                list.appendChild(el('li', {class: 'list-group-item text-muted'}, labels.allHidden));
            }
            card.appendChild(header); card.appendChild(list); column.appendChild(card); row.appendChild(column);
        });
        container.replaceChildren(row);
        // Names are map keys, never interpolated CSS selectors.
        container.querySelectorAll('ul[data-group]').forEach(node => { node.scrollTop = scroll.get(node.getAttribute('data-group')) || 0; });
        if (focusKey) {
            const controls = Array.from(container.querySelectorAll('[data-focus-key]'));
            let replacement = controls.find(node => node.getAttribute('data-focus-key') === focusKey);
            if (!replacement && visibility && active.getAttribute('data-group') !== null) {
                const groupKey = JSON.stringify(['collapse', active.getAttribute('data-group')]);
                replacement = controls.find(node => node.getAttribute('data-focus-key') === groupKey);
            }
            if (replacement) { replacement.focus({preventScroll: true}); }
        }
    }
    function renderConnectionClients(container, summary, labels) {
        const doc = container.ownerDocument, el = (tag, attrs, text) => element(doc, tag, attrs, text);
        if (!summary || !summary.rows.length) {
            container.replaceChildren(el('p', {class: 'text-muted'}, summary ? labels.empty : labels.unavailable));
            return;
        }
        const table = el('table', {class: 'table table-condensed table-striped'});
        table.appendChild(el('caption', {}, labels.shown + ': ' + summary.rows.length + ' / ' + summary.total));
        const head = el('thead'), headings = el('tr');
        [labels.source, labels.connections, labels.download, labels.upload].forEach(label => {
            headings.appendChild(el('th', {scope: 'col'}, label));
        });
        head.appendChild(headings); table.appendChild(head);
        const body = el('tbody');
        summary.rows.forEach(client => {
            const row = el('tr');
            row.appendChild(el('th', {scope: 'row'}, decodeApiText(client.source) || labels.unknown));
            row.appendChild(el('td', {}, Number(client.connections).toLocaleString()));
            row.appendChild(el('td', {}, formatBytes(client.download)));
            row.appendChild(el('td', {}, formatBytes(client.upload)));
            body.appendChild(row);
        });
        table.appendChild(body); container.replaceChildren(table);
    }
    function theme(container) {
        const probe = document.createElement('div');
        probe.setAttribute('aria-hidden', 'true');
        probe.style.cssText = 'position:absolute;visibility:hidden;pointer-events:none';
        probe.innerHTML = '<span class="text-info">x</span><span class="text-warning">x</span><table class="table"><tbody><tr><td>x</td></tr></tbody></table>';
        container.appendChild(probe);
        const text = getComputedStyle(container).color;
        const down = getComputedStyle(probe.children[0]).color;
        const up = getComputedStyle(probe.children[1]).color;
        const border = getComputedStyle(probe.querySelector('td')).borderTopColor;
        probe.remove();
        return {text, down, up, grid: border};
    }
    return {formatBytes, formatTrafficTotal, TrafficTotals, TrafficHistory, summarizeProxyLatency, theme, decodeApiText, exportSelections, logLevel, filterLogLines, ruleMatchText, copyText, Poller, runLimited, element, normalizeProxyQuery, filterProxyGroups, fullProxyGroupTestNames, renderProxyGroups, ProxyFavorites, comparisonReport, automaticTestNames, ProxySnapshots, planProxySnapshot, fastestProxy, proxyGroupSignature, renderConnectionClients, formatUptime, emptyProxyGroups, ProxyNotes};
}));
