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
    // Internal OPNsense API responses use htmlspecialchars(..., ENT_NOQUOTES).
    // Decode exactly one layer, preserving entities that are literal file data.
    function decodeApiText(value) {
        return String(value == null ? '' : value).replace(/&(amp|lt|gt);/g, function (entity) {
            return {'&amp;': '&', '&lt;': '<', '&gt;': '>'}[entity];
        });
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
    // Every dynamic value reaches textContent/setAttribute, never HTML parsing.
    function element(doc, tag, attrs, text) {
        const node = doc.createElement(tag);
        Object.keys(attrs || {}).forEach(key => node.setAttribute(key, String(attrs[key])));
        if (text !== undefined) { node.textContent = String(text); }
        return node;
    }
    function renderProxyGroups(container, groups, labels, delayText, delayClass) {
        const doc = container.ownerDocument, el = (tag, attrs, text) => element(doc, tag, attrs, text);
        const scroll = new Map();
        container.querySelectorAll('ul[data-group]').forEach(node => scroll.set(node.getAttribute('data-group'), node.scrollTop));
        const active = doc.activeElement;
        const focusKey = active && container.contains(active) ? active.getAttribute('data-focus-key') : null;
        const row = el('div', {class: 'row'});
        groups.forEach(group => {
            const name = decodeApiText(group.name);
            const column = el('div', {class: 'col-md-6', style: 'margin-bottom:15px'});
            const card = el('div', {class: 'content-box', style: 'height:300px;margin-bottom:0;display:flex;flex-direction:column'});
            const header = el('div', {style: 'padding:10px 12px;flex:0 0 auto'});
            header.appendChild(el('b', {}, name + ' '));
            header.appendChild(el('span', {class: 'label label-opnsense label-opnsense-sm label-info'}, decodeApiText(group.type)));
            const test = el('button', {type: 'button', class: 'btn btn-xs btn-default cmd-test-group pull-right',
                'data-group': name, 'data-focus-key': JSON.stringify(['group', name]), 'aria-label': labels.testGroup + ': ' + name, title: labels.testGroup});
            test.appendChild(el('i', {class: 'fa fa-tachometer fa-fw', 'aria-hidden': 'true'}));
            header.appendChild(test);
            const list = el('ul', {class: 'list-group', 'data-group': name, 'aria-label': name,
                style: 'margin-bottom:0;flex:1 1 auto;overflow-y:auto'});
            (group.members || []).forEach(member => {
                const memberName = decodeApiText(member.name);
                const item = el('li', {class: 'list-group-item' + (member.selected ? ' active' : ''),
                    style: 'padding:8px 12px;display:flex;align-items:center;gap:6px', 'data-group': name, 'data-member': memberName});
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
                item.appendChild(testMember); list.appendChild(item);
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
    return {formatBytes, TrafficHistory, theme, decodeApiText, Poller, runLimited, element, renderProxyGroups};
}));
