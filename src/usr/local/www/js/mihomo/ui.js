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
    // Internal OPNsense API responses use htmlspecialchars(..., ENT_NOQUOTES).
    // Decode exactly one layer, preserving entities that are literal file data.
    function decodeApiText(value) {
        return String(value == null ? '' : value).replace(/&(amp|lt|gt);/g, function (entity) {
            return {'&amp;': '&', '&lt;': '<', '&gt;': '>'}[entity];
        });
    }
    // Copy the observed match conditions, not a reconstructed executable PF rule.
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
            this.schedule = this.options.schedule || setTimeout;
            this.cancel = this.options.cancel || clearTimeout;
            this.timer = null;
            this.pending = false;
            this.failures = 0;
            this.stopped = false;
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
                if (!this.stopped && !this.hidden()) {
                    this.timer = this.schedule(() => this.refresh(), Math.min(this.interval * Math.pow(2, this.failures), 60000));
                }
            });
        }
        visibilityChanged() { this.refresh(); }
        stop() { this.stopped = true; this.cancel(this.timer); }
    }
    function runLimited(items, limit, worker, progress, done) {
        let next = 0, active = 0, completed = 0, failed = 0;
        function pump() {
            if (completed === items.length) { done({completed, failed}); return; }
            while (active < limit && next < items.length) {
                const item = items[next++]; active++;
                let settled = false;
                worker(item, ok => {
                    if (settled) { return; }
                    settled = true; active--; completed++; if (!ok) { failed++; }
                    progress({completed, total: items.length, failed});
                    pump();
                });
            }
        }
        pump();
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
    // Every dynamic value reaches textContent/setAttribute, never HTML parsing.
    function element(doc, tag, attrs, text) {
        const node = doc.createElement(tag);
        Object.keys(attrs || {}).forEach(key => node.setAttribute(key, String(attrs[key])));
        if (text !== undefined) { node.textContent = String(text); }
        return node;
    }
    function renderProxyGroups(container, groups, labels, delayText, delayClass, favorites, nodeOrder = 'config', collapsedGroups) {
        const doc = container.ownerDocument, el = (tag, attrs, text) => element(doc, tag, attrs, text);
        const direction = nodeOrder === 'name-asc' ? 1 : nodeOrder === 'name-desc' ? -1 : 0;
        const collator = direction ? new Intl.Collator(undefined, {numeric: true, sensitivity: 'base'}) : null;
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
        (favorites ? favorites.order(groups, 'groups') : groups).forEach((group, index) => {
            const name = decodeApiText(group.name);
            let members = group.members || [];
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
            const list = el('ul', {id: listId, class: 'list-group', 'data-group': name, 'aria-label': name,
                style: 'margin-bottom:0;flex:1 1 auto;overflow-y:auto'});
            // Keep members in the DOM so full-group latency tests still include them.
            if (collapsed) { list.setAttribute('hidden', ''); }
            if (collator) {
                // Sort decoded display names on a copy; stable ties keep controller order.
                members = members.map(member => ({member, name: decodeApiText(member.name)}))
                    .sort((a, b) => direction * collator.compare(a.name, b.name)).map(item => item.member);
            }
            // The stable favorite partition preserves name order within both sections.
            (favorites ? favorites.order(members, 'proxies') : members).forEach(member => {
                const memberName = decodeApiText(member.name);
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
                item.appendChild(el('span', {class: 'label label-opnsense label-opnsense-sm ' + delayClass(member.delay)}, delayText(member.delay)));
                const testMember = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-test', 'data-name': memberName,
                    'data-focus-key': JSON.stringify(['test', name, memberName]), 'aria-label': labels.testNode + ': ' + memberName, title: labels.testNode});
                testMember.appendChild(el('i', {class: 'fa fa-bolt fa-fw', 'aria-hidden': 'true'}));
                item.appendChild(testMember);
                const copyName = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-copy',
                    'data-copy-text': memberName, 'data-focus-key': JSON.stringify(['copy-name', name, memberName]),
                    'aria-label': labels.copyName + ': ' + memberName, title: labels.copyName});
                copyName.appendChild(el('i', {class: 'fa fa-copy fa-fw', 'aria-hidden': 'true'}));
                item.appendChild(copyName); list.appendChild(item);
            });
            card.appendChild(header); card.appendChild(list); column.appendChild(card); row.appendChild(column);
        });
        container.replaceChildren(row);
        // Names are map keys, never interpolated CSS selectors.
        container.querySelectorAll('ul[data-group]').forEach(node => { node.scrollTop = scroll.get(node.getAttribute('data-group')) || 0; });
        if (focusKey) {
            const replacement = Array.from(container.querySelectorAll('[data-focus-key]')).find(node => node.getAttribute('data-focus-key') === focusKey);
            if (replacement) { replacement.focus({preventScroll: true}); }
        }
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
    return {formatBytes, formatTrafficTotal, TrafficHistory, theme, decodeApiText, logLevel, filterLogLines, ruleMatchText, copyText, Poller, runLimited, element, renderProxyGroups, ProxyFavorites};
}));
