const assert = require('node:assert/strict');
const {TrafficHistory, formatBytes} = require('../src/usr/local/www/js/mihomo/ui.js');
assert.equal(formatBytes(738, 'en-US'), '738.0 B');
assert.equal(formatBytes(1536, 'en-US'), '1.5 KiB');
assert.equal(formatBytes(1536, 'de-DE'), '1,5 KiB');
assert.equal(formatBytes(null), '0.0 B');
assert.equal(formatBytes(NaN), '—');
const {formatTrafficTotal} = require('../src/usr/local/www/js/mihomo/ui.js');
for (const [value, human, raw] of [
    [0, '0.0 B', '0 B'], [738, '738.0 B', '738 B'], [1023, '1,023.0 B', '1,023 B'],
    [1024, '1.0 KiB', '1,024 B'], [1536, '1.5 KiB', '1,536 B'],
    [1048576, '1.0 MiB', '1,048,576 B'], [1073741824, '1.0 GiB', '1,073,741,824 B'],
    [1099511627776, '1.0 TiB', '1,099,511,627,776 B']
]) {
    assert.equal(formatTrafficTotal(value, false, 'en-US'), human);
    assert.equal(formatTrafficTotal(value, true, 'en-US'), raw);
}
assert.equal(formatTrafficTotal(1536, true, 'de-DE'), '1.536 B');
assert.equal(formatTrafficTotal(1536, false, 'de-DE'), '1,5 KiB');
assert.equal(formatTrafficTotal(1536, true, 'zh-CN'), '1,536 B');
assert.equal(formatTrafficTotal(Number.MAX_SAFE_INTEGER, true, 'en-US'), '9,007,199,254,740,991 B');
for (const invalid of [null, undefined, NaN, Infinity, -1, 1.5, '', '1536', Number.MAX_SAFE_INTEGER + 1]) {
    for (const raw of [false, true]) { assert.equal(formatTrafficTotal(invalid, raw), '—'); }
}
const history = new TrafficHistory();
assert.equal(history.add(1000, 100, 200, true).down, null);
assert.deepEqual(history.add(3000, 2100, 1200, true), {down: 1000, up: 500});
assert.equal(history.add(5000, 100, 100, true).down, null, 'counter reset must be a gap');
assert.equal(history.add(7000, 200, 200, false).down, null);
assert.equal(history.add(9000, 300, 300, true).down, null, 'recovery needs a new baseline');
assert.equal(history.add(30000, 3000, 3000, true).down, null, 'suspended polling is a gap');
for (let time = 32000; time <= 7300000; time += 2000) { history.add(time, time, time, true); }
assert(history.samples.length <= 1800);
assert(history.window(60, 7300000).every(p => p.time >= 7240000));
assert(history.window(3600, 7300000).length <= 300);
assert(new TrafficHistory([{time: Date.now(), down: -1, up: 0}]).samples.length === 0);

const decode = require('../src/usr/local/www/js/mihomo/ui.js').decodeApiText;
assert.strictEqual(decode('x --&gt; y &amp; z &lt;tag&gt;'), 'x --> y & z <tag>');
assert.strictEqual(decode('literal &amp;gt; &amp;amp; &#039;'), 'literal &gt; &amp; &#039;');

const logLevel = require('../src/usr/local/www/js/mihomo/ui.js').logLevel;
for (const level of ['debug', 'info', 'warning', 'error', 'fatal', 'panic']) {
    assert.equal(logLevel(`time="2026-11-15T12:34:56Z" level=${level} msg="中文 <tag>"`), level);
    assert.equal(logLevel(`level=${level} msg="without timestamp"`), level);
}
for (const [prefix, level] of [['DEBU', 'debug'], ['INFO', 'info'], ['WARN', 'warning'],
    ['ERRO', 'error'], ['FATA', 'fatal'], ['PANI', 'panic']]) {
    assert.equal(logLevel(`\x1b[33m${prefix}\x1b[0m[2026-11-15T12:34:56Z] message`), level);
}
assert.equal(logLevel('time=2026-11-15T12:34:56Z level=warn msg="alias"'), 'warning');
for (const line of ['', 'subscription error', '[2026-11-15 12:34:56] task finished (exit=1)',
    'msg="level=error"', 'message level=error', 'time="level=error" msg="no level"',
    'time="unterminated level=error', 'level=errorish msg="unknown"', 'level=trace msg="unknown"',
    '    at example.js:1', 'INFO is only a word', 'warning: plain text']) {
    assert.equal(logLevel(line), 'unknown', line);
}
assert.equal(logLevel('time="2026-11-15T12:34:56Z" level=info msg="level=error WARN[123]"'), 'info');
console.log('Log severity parsing: structured headers, console colors, aliases and unclassified text passed');

console.log('UI history, formatting and API text decoding: all checks passed');

// Exercise the actual log view script with delayed API responses, without a browser
// or an appliance. Requests and controls are the boundary, not copied queue logic.
const fs = require('node:fs');
const vm = require('node:vm');
const controls = new Map(), requests = [], fakeDocument = {hidden: false};
let logTimer, logDecodes = 0;
function control(selector) {
    if (!controls.has(selector)) {
        const item = {value: '', checked: false, label: '', handlers: {}, top: 100,
            writes: 0, textWrites: 0, layoutReads: 0, scrollWrites: 0,
            0: {scrollHeight: 100}, val(value) { if (value === undefined) { return this.value; } this.writes++; this.value = value; return this; },
            text(value) { this.textWrites++; this.label = value; return this; },
            prop(key, value) { if (value === undefined) { return this[key]; } this[key] = value; return this; },
            css(styles) {
                this.styles = {...this.styles, ...styles};
                if (this.wrapHeights) { this[0].scrollHeight = this.wrapHeights[this.wrap]; }
                return this;
            },
            on(event, fn) { this.handlers[event] = fn; return this; },
            change(fn) { return this.on('change', fn); }, click(fn) { return this.on('click', fn); },
            scrollTop(value) { if (value === undefined) { this.layoutReads++; return this.top; } this.scrollWrites++; this.top = value; return this; },
            outerHeight() { this.layoutReads++; return 50; }};
        controls.set(selector, item);
    }
    return controls.get(selector);
}
control('#log-source').value = 'mihomo';
control('#log-lines').value = '300';
control('#log-level').value = 'all';
const logView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/log.volt'), 'utf8');
const logScript = logView.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
const logDownloads = [];
vm.runInNewContext(logScript, {
    document: fakeDocument,
    Blob: class { constructor(parts) { logDownloads.push(parts.join('')); } },
    URL: {createObjectURL: () => 'blob:log-test', revokeObjectURL() {}},
    $: selector => selector === fakeDocument ? {ready: fn => fn()} : control(selector),
    ajaxGet: (url, params, done) => requests.push({params, done}),
    setInterval: fn => { logTimer = fn; }, MihomoUI: {logLevel, decodeApiText: value => { logDecodes++; return decode(value); }}
});
assert.equal(requests.length, 1);
control('#log-source').value = 'subscription';
control('#log-source').handlers.change();
requests[0].done({status: 'ok', content: 'stale core log'}, 'success');
assert.equal(requests.length, 2, 'A source switch queues a read even with auto refresh paused');
assert.equal(requests[1].params.key, 'subscription');
assert(!control('#log-viewer').value.includes('stale'), 'Never render a response for the old source');
requests[1].done({status: 'ok', content: 'new subscription log\nFind Me\n'}, 'success');
control('#log-filter').value = 'find me';
control('#log-filter').handlers.input();
assert.equal(control('#log-viewer').value, 'Find Me');
control('#log-filter').value = '';
control('#refreshAct').handlers.click();
control('#log-lines').value = '1000';
control('#log-lines').handlers.change();
requests[2].done({status: 'ok', content: 'stale line count'}, 'success');
assert.equal(requests[3].params.lines, '1000');
control('#refreshAct').handlers.click(); // Same selection queued while the request is slow.
requests[3].done({status: 'ok', content: 'current log'}, 'success');
assert.equal(control('#log-viewer').value, 'current log', 'Queued refresh must not starve a valid response');
assert.equal(requests.length, 5);
requests[4].done(null, 'error');
assert.equal(control('#log-viewer').value, 'current log', 'Read failures retain the last valid content');
console.log('Log source/line switching, paused refresh, filtering and slow responses: all checks passed');

// Unchanged polls should leave the decoded lines and textarea alone, including
// after filtering or a failed read. Exercise the real timer and request callback.
control('#log-auto-refresh').checked = true;
const viewer = control('#log-viewer'), logState = control('#log-state');
const logWork = () => [logDecodes, viewer.writes, viewer.layoutReads, viewer.scrollWrites,
    control('#log-match-state').textWrites];
const respondLog = content => requests.at(-1).done({status: 'ok', content}, 'success');
const beforeRecovery = logWork(), stateWrites = logState.textWrites;
logTimer(); respondLog('current log');
assert.deepEqual(logWork(), beforeRecovery, 'Identical recovery skips decoding, filtering, DOM writes and layout');
assert.equal(logState.textWrites, stateWrites + 1, 'Successful unchanged reads still update freshness/error status');
const content = 'first &amp; line\nFind Me\n';
logTimer(); respondLog(content);
assert.equal(viewer.value, 'first & line\nFind Me');
control('#log-filter').value = 'find me';
control('#log-filter').handlers.input();
assert.equal(viewer.value, 'Find Me');
viewer.top = 0;
const filteredWork = logWork();
for (let i = 0; i < 3; i++) { logTimer(); respondLog(content); }
assert.deepEqual(logWork(), filteredWork, 'Repeated payloads retain the current filter and scroll position');
assert.equal(viewer.value, 'Find Me');
// A queued manual refresh must still run and scroll on an unchanged response.
logTimer();
control('#refreshAct').handlers.click();
const beforeQueued = requests.length;
respondLog(content);
assert.equal(requests.length, beforeQueued + 1);
respondLog(content);
assert.equal(viewer.top, viewer[0].scrollHeight);
assert.equal(viewer.writes, filteredWork[1], 'Manual refresh does not rewrite unchanged text');
control('#log-filter').value = '';
control('#log-filter').handlers.input();
assert.equal(viewer.value, 'first & line\nFind Me', 'Filtering still uses the retained full log');
viewer.top = 0;
logTimer(); respondLog('changed\n');
assert.equal(viewer.value, 'changed');
assert.equal(viewer.top, 0, 'Changed polls preserve scrolling when reading older lines');
viewer.top = 100;
logTimer(); respondLog('newest\n');
assert.equal(viewer.top, viewer[0].scrollHeight, 'Changed polls still follow the log at the bottom');
control('#log-source').value = 'mihomo';
control('#log-source').handlers.change();
assert.equal(viewer.value, '');
respondLog('newest\n');
assert.equal(viewer.value, 'newest', 'Changing source invalidates the cache even for identical content');
control('#log-lines').value = '100';
control('#log-lines').handlers.change();
respondLog('');
assert.equal(viewer.value, '', 'An empty log clears previously rendered lines');
const emptyWork = logWork();
logTimer(); respondLog('');
assert.deepEqual(logWork(), emptyWork, 'Empty logs also skip unchanged poll work');
console.log('Unchanged log polling, recovery, filtering, queued scrolling and cache invalidation: all checks passed');

// Run the real wrap control against long, unbroken Unicode text. Only presentation
// may change, even when polling has no new content or a filter is active.
assert.match(logView, /<label\b[^>]*for="log-wrap"[^>]*>[\s\S]*?lang\._\('Wrap lines'\)/);
assert.match(logView, /<input\b[^>]*id="log-wrap"[^>]*type="checkbox"[^>]*aria-controls="log-viewer"[^>]*checked/);
assert.match(logView, /<textarea\b[^>]*id="log-viewer"[^>]*wrap="soft"/);
assert.match(logView, /white-space: pre-wrap; overflow-wrap: anywhere;/);
const wrapControl = control('#log-wrap');
assert.equal(wrapControl.checked, true, 'Each page visit starts wrapped');
const longLog = '中文 https://example.invalid/' + 'long-path'.repeat(100) + '\t<&>\nsecond line\n';
logTimer(); respondLog(longLog);
viewer[0].selectionStart = 3; viewer[0].selectionEnd = 70;
viewer.wrapHeights = {soft: 600, off: 150};
viewer[0].scrollHeight = 600; viewer.top = 550;
const beforeWrap = [requests.length, logDecodes, viewer.writes, control('#log-match-state').textWrites];
const toggleWrap = enabled => { wrapControl.checked = enabled; wrapControl.handlers.change(); };
toggleWrap(false);
assert.equal(viewer.wrap, 'off');
assert.equal(viewer.styles['white-space'], 'pre');
assert.equal(viewer.styles['overflow-wrap'], 'normal', 'Unbroken URLs must also stop wrapping');
assert.equal(viewer.top, 150, 'Follow the bottom after shrinking the wrapped content');
assert.deepEqual([requests.length, logDecodes, viewer.writes, control('#log-match-state').textWrites], beforeWrap,
    'Wrapping neither fetches nor decodes nor rewrites/recounts the log');
assert.equal(viewer.value, longLog.trimEnd());
assert.deepEqual([viewer[0].selectionStart, viewer[0].selectionEnd], [3, 70]);
toggleWrap(true);
assert.equal(viewer.wrap, 'soft');
assert.equal(viewer.styles['white-space'], 'pre-wrap');
assert.equal(viewer.styles['overflow-wrap'], 'anywhere');
assert.equal(viewer.top, 600, 'Follow the bottom after expanding the wrapped content');
viewer.top = 0;
toggleWrap(false);
assert.equal(viewer.top, 0, 'Do not force a reader of older entries to the bottom');
control('#log-filter').value = 'second'; control('#log-filter').handlers.input();
logTimer(); respondLog(longLog);
assert.equal(viewer.value, 'second line');
assert.equal(viewer.wrap, 'off', 'Filtering and unchanged polls retain the wrapping choice');
control('#log-source').value = 'subscription'; control('#log-source').handlers.change();
respondLog('second source\n');
assert.equal(viewer.wrap, 'off', 'Source switches and changed responses retain the wrapping choice');
assert.equal(viewer.value, 'second source');
fakeDocument.createElement = tag => { assert.equal(tag, 'a'); return {click() {}}; };
control('#downloadAct').handlers.click();
assert.equal(requests.at(-1).params.lines, 5000);
respondLog(longLog);
assert.equal(logDownloads.at(-1), longLog, 'Download keeps full logical lines regardless of wrapping/filter');
control('#log-filter').value = ''; control('#log-filter').handlers.input();
toggleWrap(true);
assert.equal(viewer.value, 'second source', 'Toggling back does not replace the current log');
console.log('Log wrapping: defaults, long Unicode lines, selection, tail following, filtering, polling, source changes and downloads passed');

// Timestamp visibility runs through the real view, retaining original lines for
// search/download and leaving unrecognized prefixes and message dates intact.
const hideTime = control('#log-hide-timestamps');
assert.match(logView, /<label[^>]*><input id="log-hide-timestamps" type="checkbox">/,
    'Timestamp hiding is labelled and off on each page visit');
const timestampLines = [
    'time="2026-11-15T12:34:56.123456789+08:00" level=info msg="connected &amp; ready"',
    'time="2026-11-15T04:34:56Z" level=warning msg="retry at 2026-11-16"',
    'time="2026-11-15T04:34:56.001-05:00" level=debug msg="trace"',
    '[2026-11-15 12:34:56] Subscription task finished (exit=0).',
    'plain message with time="2026-11-15T04:34:56Z" inside',
    '    continuation [2026-11-15 12:34:56]',
    'time="unknown" level=info msg="keep unknown prefix"',
    '[INFO] Keep severity',
    '[2026-11-15 12:34:56] [2026-11-16 12:34:56] Message date',
    ''
];
const timestampContent = timestampLines.join('\n') + '\n';
control('#log-source').value = 'mihomo'; control('#log-source').handlers.change();
respondLog(timestampContent);
const originalLog = viewer.value;
assert.equal(originalLog, decode(timestampLines.join('\n')));
control('#log-auto-refresh').checked = false;
viewer.top = 17;
toggleWrap(false);
const timestampRequests = requests.length, timestampDecodes = logDecodes;
hideTime.checked = true; hideTime.handlers.change();
assert.equal(viewer.value, [
    'level=info msg="connected & ready"',
    'level=warning msg="retry at 2026-11-16"',
    'level=debug msg="trace"',
    'Subscription task finished (exit=0).',
    ...timestampLines.slice(4, 8),
    '[2026-11-16 12:34:56] Message date', ''
].join('\n'));
assert.equal(viewer.top, 17, 'Toggling preserves the scroll offset');
assert.equal(requests.length, timestampRequests, 'Toggling while paused needs no fetch');
assert.equal(logDecodes, timestampDecodes, 'Toggling uses the decoded cache');
assert.equal(viewer.wrap, 'off', 'Timestamp hiding does not change the wrapping choice');
assert.equal(control('#log-match-state').label, '10 / 10');
control('#log-filter').value = '+08:00'; control('#log-filter').handlers.input();
assert.equal(viewer.value, 'level=info msg="connected & ready"', 'Hidden timestamps remain searchable');
assert.equal(control('#log-match-state').label, '1 / 10');
control('#log-filter').value = 'no match'; control('#log-filter').handlers.input();
assert.equal(viewer.value, '');
control('#log-filter').value = ''; control('#log-filter').handlers.input();
control('#refreshAct').handlers.click(); respondLog(timestampContent);
assert(!viewer.value.startsWith('time='), 'Unchanged refresh retains timestamp hiding');
fakeDocument.createElement = () => ({click() {}});
control('#downloadAct').handlers.click();
assert.equal(requests.at(-1).params.lines, 5000);
respondLog(timestampContent);
assert.equal(logDownloads.at(-1), decode(timestampContent), 'Downloads retain full timestamps and trailing newlines');
hideTime.checked = false; hideTime.handlers.change();
assert.equal(viewer.value, originalLog, 'Showing timestamps restores exact decoded content');
hideTime.checked = true; hideTime.handlers.change();
control('#log-source').value = 'subscription'; control('#log-source').handlers.change();
assert.equal(viewer.value, '');
respondLog('[2026-11-15 13:00:00] New subscription task\n');
assert.equal(viewer.value, 'New subscription task', 'Source changes retain the choice for new content');
control('#log-lines').value = '300'; control('#log-lines').handlers.change();
respondLog('[2026-11-15 13:01:00] Finished\n');
assert.equal(viewer.value, 'Finished', 'Line count changes retain timestamp hiding');
control('#refreshAct').handlers.click(); requests.at(-1).done(null, 'error');
hideTime.checked = false; hideTime.handlers.change();
assert.equal(viewer.value, '[2026-11-15 13:01:00] Finished', 'Failed reads retain restorable timestamps');
console.log('Log timestamp toggle: defaults, formats, paused rendering, search, downloads and refreshes passed');

control('#log-auto-refresh').checked = true;
assert.match(logView, /<label for="log-level"/);
assert.match(logView, /<option value="all" selected="selected">/);
const levelControl = control('#log-level');
const severityLines = [
    'time="2026-11-15T12:34:56Z" level=info msg="DNS level=error"',
    'time="2026-11-15T12:34:57Z" level=warning msg="DNS &amp; retry"',
    'time="2026-11-15T12:34:58Z" level=error msg="DNS &lt;failed&gt;"',
    'time="2026-11-15T12:34:59Z" level=error msg="TCP failed"',
    '订阅完成', '    continuation without level'
];
logTimer(); respondLog(severityLines.join('\n') + '\n');
assert.equal(viewer.value, decode(severityLines.join('\n')), 'All levels is lossless by default');
control('#log-auto-refresh').checked = false;
const requestsBeforeLevel = requests.length;
levelControl.value = 'error'; levelControl.handlers.change();
assert.equal(viewer.value, decode(severityLines.slice(2, 4).join('\n')));
assert.equal(control('#log-match-state').label, '2 / 6');
control('#log-filter').value = 'dns'; control('#log-filter').handlers.input();
assert.equal(viewer.value, decode(severityLines[2]), 'Text and severity filters intersect');
assert.equal(control('#log-match-state').label, '1 / 6');
levelControl.value = 'warning'; levelControl.handlers.change();
assert.equal(viewer.value, decode(severityLines[1]));
levelControl.value = 'debug'; levelControl.handlers.change();
assert.equal(viewer.value, '', 'A level with no matches clears the display');
assert.equal(control('#log-match-state').label, 'translated');
control('#log-filter').value = ''; control('#log-filter').handlers.input();
levelControl.value = 'unknown'; levelControl.handlers.change();
assert.equal(viewer.value, severityLines.slice(4).join('\n'), 'Unstructured lines remain accessible');
logTimer();
assert.equal(requests.length, requestsBeforeLevel, 'Changing filters while paused makes no requests');
control('#refreshAct').handlers.click();
levelControl.value = 'error'; levelControl.handlers.change();
respondLog('level=info msg="new"\nlevel=error msg="new"\n');
assert.equal(viewer.value, 'level=error msg="new"', 'In-flight responses use the current severity');
control('#log-auto-refresh').checked = true;
const levelWork = logWork();
logTimer(); respondLog('level=info msg="new"\nlevel=error msg="new"\n');
assert.deepEqual(logWork(), levelWork, 'Unchanged polls preserve severity filtering without DOM work');
control('#log-lines').value = '300'; control('#log-lines').handlers.change();
respondLog('level=info msg="older"\nlevel=error msg="older"\n');
assert.equal(viewer.value, 'level=error msg="older"', 'Line-count changes retain severity');
control('#log-source').value = 'subscription'; control('#log-source').handlers.change();
assert.equal(viewer.value, '');
respondLog('订阅完成\n');
assert.equal(viewer.value, '', 'Source changes retain severity without showing stale entries');
levelControl.value = 'all'; levelControl.handlers.change();
assert.equal(viewer.value, '订阅完成', 'All restores unclassified subscription output');
console.log('Log severity controls: defaults, counts, search intersection, pause, polling and source/line changes passed');

// Severity is decided on the source text before presentation changes.
control('#log-source').value = 'mihomo'; control('#log-source').handlers.change();
respondLog(severityLines.join('\n') + '\n');
control('#log-auto-refresh').checked = false;
levelControl.value = 'error'; levelControl.handlers.change();
control('#log-filter').value = '12:34:58Z'; control('#log-filter').handlers.input();
hideTime.checked = true; hideTime.handlers.change();
toggleWrap(false);
assert.equal(viewer.value, 'level=error msg="DNS <failed>"',
    'Severity and full-source text search still intersect while timestamp is hidden and wrapping is off');
assert.equal(viewer.wrap, 'off');
assert.equal(control('#log-match-state').label, '1 / 6');
control('#downloadAct').handlers.click();
assert.equal(requests.at(-1).params.lines, 5000);
respondLog(severityLines.join('\n') + '\n');
assert.equal(logDownloads.at(-1), decode(severityLines.join('\n')) + '\n',
    'Downloads retain all severities, original timestamps and trailing newlines');
control('#log-filter').value = ''; control('#log-filter').handlers.input();
levelControl.value = 'all'; levelControl.handlers.change();
hideTime.checked = false; hideTime.handlers.change();
toggleWrap(true);
control('#log-auto-refresh').checked = true;
console.log('Severity with timestamp hiding, full-source search, wrapping and downloads passed');


// The same renderer used by the dashboard runs against a strict DOM fixture.
// HTML parsing is deliberately unavailable: dynamic names must be text/attributes.
const UI = require('../src/usr/local/www/js/mihomo/ui.js');
class DomNode {
    constructor(doc, tag) { this.ownerDocument = doc; this.tagName = tag; this.attrs = {}; this.children = []; this.scrollTop = 0; this.textContent = ''; }
    setAttribute(key, value) { this.attrs[key] = value; }
    getAttribute(key) { return Object.hasOwn(this.attrs, key) ? this.attrs[key] : null; }
    appendChild(node) { this.children.push(node); return node; }
    replaceChildren(...nodes) { this.children = nodes; }
    contains(node) { return this === node || this.children.some(child => child.contains(node)); }
    set innerHTML(_) { throw new Error('Dynamic HTML must never be parsed'); }
    querySelectorAll(selector) {
        const match = selector.match(/^(\w+)?\[([^\]]+)\]$/);
        assert(match, 'Only static attribute selectors are expected');
        const result = [];
        this.children.forEach(child => {
            if ((!match[1] || child.tagName === match[1]) && child.getAttribute(match[2]) !== null) { result.push(child); }
            result.push(...child.querySelectorAll(selector));
        });
        return result;
    }
    focus(options) { assert.equal(options.preventScroll, true); this.ownerDocument.activeElement = this; }
}
const doc = {activeElement: null, createElement(tag) { return new DomNode(this, tag); }};
const groupBox = doc.createElement('div');
const names = ['name" data-unexpected="value', "single' quote", '<tag>&value', '001', '中文\\name', 'literal &gt; 😀\nnext\tline'];
const encode = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const groups = names.map(name => ({name: encode(name), now: encode(name), type: 'Selector', members: [{name: encode(name), type: 'test', selected: true, delay: 20}]}));
const render = () => UI.renderProxyGroups(groupBox, groups, {testGroup: 'Test group', testNode: 'Test node', memberCount: 'Members: %s',
    copyName: 'Copy proxy name', copySelection: 'Copy group selection'}, value => value + ' ms', () => 'label-success');
render();
const lists = groupBox.querySelectorAll('ul[data-group]');
assert.deepEqual(lists.map(node => node.getAttribute('data-group')), names);
const members = groupBox.querySelectorAll('li[data-member]');
assert.deepEqual(members.map(node => node.getAttribute('data-member')), names);
assert(members.every(node => !Object.hasOwn(node.attrs, 'data-unexpected')));
const buttons = groupBox.querySelectorAll('button[data-focus-key]');
assert.equal(buttons.length, names.length * 5);
assert(buttons.every(node => node.attrs.type === 'button'), 'Selection has native keyboard activation');
assert.equal(buttons[2].attrs['aria-pressed'], 'true');
assert.equal(buttons[3].attrs['aria-label'], 'Test node: ' + names[0]);
assert.equal(buttons[2].children[1].textContent, ' ' + names[0] + ' ');
const copyButtons = groupBox.querySelectorAll('button[data-copy-text]');
names.forEach((name, i) => {
    assert.equal(copyButtons[i * 2].attrs['data-copy-text'], JSON.stringify(name) + ': ' + JSON.stringify(name) + '\n');
    assert.equal(copyButtons[i * 2 + 1].attrs['data-copy-text'], name, 'Copy names exactly, decoding only one API layer');
    assert.equal(copyButtons[i * 2 + 1].attrs['aria-label'], 'Copy proxy name: ' + name);
});
lists[0].scrollTop = 172;
doc.activeElement = copyButtons[1];
render();
assert.equal(groupBox.querySelectorAll('ul[data-group]')[0].scrollTop, 172);
assert.notEqual(doc.activeElement, copyButtons[1], 'Refresh replaces nodes');
assert.equal(doc.activeElement.attrs['data-focus-key'], copyButtons[1].attrs['data-focus-key'], 'Refresh restores copy-button focus by exact name');
assert(groupBox.contains(doc.activeElement));
groups[0].now = '';
groups[1].now = encode('new <selection> &gt;');
render();
assert.equal(groupBox.querySelectorAll('button[data-copy-text]')[0].disabled, true, 'No selection must not copy an empty mapping');
assert.equal(groupBox.querySelectorAll('button[data-copy-text]')[2].attrs['data-copy-text'],
    JSON.stringify(names[1]) + ': "new <selection> &gt;"\n', 'Polling updates the selection to copy');

// Counts describe direct entries, not recursively expanded or healthy proxies.
const countBox = doc.createElement('div');
const countGroups = [
    {name: encode('<Group>&'), type: 'Selector', members: [
        {name: 'Nested', type: 'URLTest'}, {name: 'DIRECT', type: 'Direct'},
        {name: 'REJECT', type: 'Reject'}, {name: 'Offline', delay: 0}
    ]},
    {name: 'Nested', type: 'URLTest', members: [{name: 'Shared'}]},
    {name: 'Empty', members: []}, {name: 'Missing'}, {name: 'Null', members: null}
];
const originalCountGroups = JSON.stringify(countGroups);
UI.renderProxyGroups(countBox, countGroups, {memberCount: '成员数：%s'}, String, () => '');
const countBadges = box => box.querySelectorAll('span[data-member-count]');
assert.deepEqual(countBadges(countBox).map(node => node.textContent),
    ['成员数：4', '成员数：1', '成员数：0', '成员数：0', '成员数：0']);
assert.deepEqual(countBadges(countBox).map(node => node.attrs['data-member-count']), ['4', '1', '0', '0', '0']);
assert.equal(JSON.stringify(countGroups), originalCountGroups, 'Counting must not mutate API data');
assert.equal(countBox.children[0].children[0].children[0].children[0].children[0].textContent, '<Group>& ');
console.log('Group member counts: direct entries, empty/missing members, translated text and unchanged data passed');

// Fake timers prove non-overlap, hidden pause/resume, exponential retry and recovery.
let hidden = false, callback, calls = 0, scheduled = null;
const polling = new UI.Poller(done => { calls++; callback = done; }, 2000, {
    hidden: () => hidden, schedule: (fn, delay) => { scheduled = {fn, delay}; return scheduled; },
    cancel: timer => { if (timer === scheduled) { scheduled = null; } }
});
polling.refresh(); polling.refresh();
assert.equal(calls, 1);
callback(false); assert.equal(scheduled.delay, 4000);
scheduled.fn(); callback(false); assert.equal(scheduled.delay, 8000);
for (let i = 0; i < 6; i++) { scheduled.fn(); callback(false); }
assert.equal(scheduled.delay, 60000);
hidden = true; polling.visibilityChanged(); assert.equal(scheduled, null);
const countBeforeHide = calls; polling.refresh(); assert.equal(calls, countBeforeHide);
hidden = false; polling.visibilityChanged(); callback(true); assert.equal(scheduled.delay, 2000);
scheduled.fn(); hidden = true; callback(true); assert.equal(scheduled, null, 'An in-flight response cannot rearm a hidden page');
hidden = false; polling.visibilityChanged(); callback(true);
polling.stop(); assert.equal(scheduled, null);
polling.refresh(); assert.equal(polling.pending, false);

let activeTests = 0, peakTests = 0, nextTest = 0, result;
const completions = [], progress = [];
UI.runLimited(Array.from({length: 12}, (_, i) => i), 3, (item, done) => {
    activeTests++; peakTests = Math.max(peakTests, activeTests);
    completions.push(ok => { activeTests--; done(ok); });
}, state => progress.push(state), state => { result = state; });
assert.equal(completions.length, 3);
while (nextTest < completions.length) { completions[nextTest++](nextTest % 4 !== 0); }
assert.equal(peakTests, 3);
assert.deepEqual(result, {completed: 12, failed: 3});
assert.deepEqual(progress.map(item => item.completed), Array.from({length: 12}, (_, i) => i + 1));
const subscriptionView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/subscription.volt'), 'utf8');
assert(subscriptionView.includes('/api/mihomo/subscription/status'));
assert(!subscriptionView.includes('/api/mihomo/dashboard/runtime_status'));
console.log('DOM names, native keyboard controls, focus/scroll, polling backoff/visibility and bounded latency tests: all checks passed');

// Execute the actual settings save/apply function: stale saves must never apply,
// and a successful model save must pass its new version to the next write.
const settingsView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt'), 'utf8');
const applyFunction = settingsView.match(/        function applySettings\(\) \{[\s\S]*?\n        \}/)[0].replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
const applyHistoryScript = settingsView.match(/        const applyHistory = \[\];[\s\S]*?(?=        function applySettings)/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
let versionValue = 'original-version';
const writeRequests = [], messages = [];
class SettingsNode {
    constructor() { this.children = []; this.label = ''; }
    prop() { return this; }
    val(value) { versionValue = value; return this; }
    text(value) { if (value === undefined) { return this.label; } this.label = value; return this; }
    empty() { this.children = []; return this; }
    append(node) { this.children.push(node); return this; }
    attr() { return this; }
    html() { throw new Error('History must render labels as text'); }
}
const historyBody = new SettingsNode();
const fieldLabel = new SettingsNode().text('Controller <secret> & key');
let changedFields = ['mihomo.general.secret', 'mihomo.managed'];
const settingsContext = {
    $: selector => selector === '#settings-history-body' ? historyBody : selector === fieldLabel ? fieldLabel : new SettingsNode(),
    document: {getElementById: id => { assert.equal(id, 'control_label_mihomo.general.secret'); return fieldLabel; }},
    MANAGED_INPUT: 'mihomo.managed',
    syncManagedHidden: () => {}, getFormData: () => ({version: versionValue, mihomo: {secret: 'do-not-retain-test-value'}}),
    ajaxCall: (url, data, done) => writeRequests.push({url, data, done}),
    handleFormValidation: () => {}, showResult: (...args) => messages.push(args),
    MihomoUI: UI, BootstrapDialog: {TYPE_DANGER: 'danger', TYPE_SUCCESS: 'success'},
    formChanges: () => changedFields, reloadForm: () => {}, loadRawConfig: () => {}
};
vm.runInNewContext(applyHistoryScript + applyFunction, settingsContext);
const historyRows = () => historyBody.children.map(row => row.children.map(cell => cell.label));
assert.deepEqual(historyRows(), [['No settings applies on this page yet.']]);
vm.runInNewContext('applySettings();', settingsContext);
assert.equal(historyRows()[0][2], 'Saving settings');
assert.equal(writeRequests[0].data.version, 'original-version');
writeRequests[0].done({status: 'failed', message: 'Configuration changed. Reload before saving.'}, 'success');
assert.equal(writeRequests.length, 1, 'A stale model cannot reach apply');
assert.equal(messages.at(-1)[2], 'danger');
assert.equal(historyRows()[0][2], 'Save failed');
assert.equal(historyRows()[0][1], 'Controller <secret> & key, Write locks');
vm.runInNewContext('applySettings();', settingsContext);
changedFields = []; // Later edits must not change the captured attempt labels.
writeRequests[1].done({result: 'saved', version: 'after-model-save'}, 'success');
assert.equal(historyRows()[0][2], 'Applying settings');
assert.equal(writeRequests[2].url, '/api/mihomo/settings/apply');
assert.equal(writeRequests[2].data.version, 'after-model-save');
writeRequests[2].done({status: 'partial', state: 'partial', message: 'Cron failed after configuration was saved.'}, 'success');
assert.equal(messages.at(-1)[2], 'danger', 'Partial completion is not reported as success');
assert.equal(versionValue, 'after-model-save');
assert.equal(historyRows()[0][2], 'Settings partly applied');
assert.equal(historyRows()[0][1], 'Controller <secret> & key, Write locks');

// Each attempt adds exactly the existing save/apply requests, with no history API.
for (const [state, label] of [
    ['completed', 'Settings applied'], ['unchanged', 'No file changes needed'],
    ['accepted', 'Restart accepted; readiness unconfirmed'], ['failed', 'Apply failed']
]) {
    const before = writeRequests.length;
    vm.runInNewContext('applySettings();', settingsContext);
    writeRequests[before].done({result: 'saved', version: 'next-version'}, 'success');
    writeRequests[before + 1].done({status: state === 'failed' ? 'failed' : 'ok', state, message: 'do-not-retain-server-message'}, 'success');
    assert.equal(writeRequests.length, before + 2);
    assert.equal(historyRows()[0][1], 'Reapply saved settings');
    assert.equal(historyRows()[0][2], label);
    assert(!Number.isNaN(Date.parse(historyRows()[0][0])));
}
for (const [data, status] of [[null, 'error'], [{status: 'ok'}, 'success'],
    [{status: 'ok', state: 'partial'}, 'success'], [{status: 'ok', state: 'completed'}, 'error']]) {
    vm.runInNewContext('applySettings();', settingsContext);
    writeRequests.at(-1).done({result: 'saved', version: 'next-version'}, 'success');
    writeRequests.at(-1).done(data, status);
    assert.equal(historyRows()[0][2], 'Outcome unconfirmed; check current settings before retrying');
}
// A failed transport during save must not send apply or claim no changes occurred.
const requestsBeforeLostSave = writeRequests.length;
vm.runInNewContext('applySettings();', settingsContext);
writeRequests.at(-1).done(null, 'error');
assert.equal(writeRequests.length, requestsBeforeLostSave + 1);
assert.equal(historyRows()[0][2], 'Outcome unconfirmed; check current settings before retrying');
vm.runInNewContext('applySettings();', settingsContext);
writeRequests.at(-1).done({result: 'saved'}, 'success'); // Missing version cannot confirm the save.
assert.equal(writeRequests.length, requestsBeforeLostSave + 2);
assert.equal(historyRows()[0][2], 'Outcome unconfirmed; check current settings before retrying');
assert.equal(historyRows().length, 10);
assert(!historyRows().some(row => row[2] === 'Save failed'), 'Oldest attempt is evicted');
const retainedHistory = vm.runInNewContext('JSON.stringify(applyHistory)', settingsContext);
assert(!retainedHistory.includes('do-not-retain'));
assert(!retainedHistory.includes('Cron failed'));
assert(!retainedHistory.includes('version'));
assert(settingsView.includes('Reloading clears this list.'));
assert(settingsView.includes('id="settings-history-body"'));
console.log('Recent settings applies: bounded history, captured labels, outcomes, transport uncertainty and privacy passed');

// Exercise the real overview request function, including its metadata cadence.
const indexView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/index.volt'), 'utf8');
const overviewFunction = indexView.match(/        function loadOverview\(done\) \{[\s\S]*?\n        \}/)[0];
const overviewRequests = [];
let now = 100000;
const overviewContext = {
    Date: {now: () => now}, ajaxGet: (url, data, done) => overviewRequests.push({url, data, done}),
    renderOverview: () => {}, drawTraffic: () => {}, trafficHistory: {add: () => {}}, $: () => ({text: () => {}})
};
vm.runInNewContext('let lastMetadata = 0;\n' + overviewFunction + '\nloadOverview();', overviewContext);
assert.equal(overviewRequests[0].data.metadata, 1);
overviewRequests[0].done({runtime: {ready: true}}, 'success');
now += 2000; vm.runInNewContext('loadOverview();', overviewContext);
assert.equal(overviewRequests[1].data.metadata, 0);
overviewRequests[1].done({runtime: {ready: true}}, 'success');
now += 30000; vm.runInNewContext('loadOverview();', overviewContext);
assert.equal(overviewRequests[2].data.metadata, 1);
console.log('Settings stale-write/version handoff, partial-result feedback and overview metadata cadence: all checks passed');

// Exercise the real chart redraw: repeated polls and range changes reuse locale
// formatters while preserving localized labels, timestamps and traffic gaps.
const trafficScript = indexView.match(/        let trafficRange = 60;[\s\S]*?\n        function drawTraffic\(\) \{[\s\S]*?\n        \}/)[0]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
const trafficSamples = Array.from({length: 300}, (_, i) => ({
    time: Date.UTC(2026, 0, 1, 12, 0, i * 2), down: i === 10 ? null : i, up: i * 2
}));
for (const locale of ['en-US', 'de-DE']) {
    let localeSetups = 0, redraws = 0;
    const chart = {data: {labels: [], datasets: [{data: []}, {data: []}]},
        update(mode) { assert.equal(mode, 'none'); redraws++; }};
    const chartContext = {
        Date: class extends Date {
            toLocaleTimeString(locales, options) {
                localeSetups++;
                return super.toLocaleTimeString(locale, options);
            }
        },
        Intl: {DateTimeFormat: function (locales, options) {
            localeSetups++;
            return new Intl.DateTimeFormat(locale, options);
        }},
        gTrafficChart: chart, trafficHistory: {window: () => trafficSamples},
        $: () => ({text: () => {}})
    };
    vm.createContext(chartContext);
    vm.runInContext(trafficScript, chartContext);
    for (const range of [60, 60, 300, 900, 3600, 60]) {
        vm.runInContext('trafficRange = ' + range + '; drawTraffic();', chartContext);
        const expected = new Intl.DateTimeFormat(locale, {
            hour: '2-digit', minute: '2-digit', second: range <= 300 ? '2-digit' : undefined
        });
        assert.deepEqual(Array.from(chart.data.labels), trafficSamples.map(point => expected.format(point.time)));
        assert.deepEqual(Array.from(chart.data.datasets[0].data), trafficSamples.map(point => point.down));
        assert.deepEqual(Array.from(chart.data.datasets[1].data), trafficSamples.map(point => point.up));
    }
    assert.equal(redraws, 6);
    assert(localeSetups <= 2, 'Repeated redraws must not set up locale formatting for every chart label');
}
console.log('Traffic chart localized labels, gaps and formatter reuse: all checks passed');

// Run the real totals control, render and request paths together. A display change
// must use the latest response without adding requests or traffic-history samples.
const totalsScript = indexView.slice(indexView.indexOf('        let latestTotals = null;'),
    indexView.indexOf(overviewFunction) + overviewFunction.length)
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
const totalControls = new Map(), totalRequests = [], totalHistory = new UI.TrafficHistory();
let totalsNow = 100000, chartDraws = 0, historySaves = 0;
function totalControl(selector) {
    if (!totalControls.has(selector)) {
        totalControls.set(selector, {
            label: '—', checked: true, handlers: {}, // Simulate a browser-restored checkbox.
            prop(key, value) { if (value === undefined) { return this[key]; } this[key] = value; return this; },
            text(value) { this.label = value; return this; },
            on(event, handler) { this.handlers[event] = handler; return this; },
            data() { return false; }, val() { return this; }
        });
    }
    return totalControls.get(selector);
}
const totalsContext = {
    $: totalControl, Date: {now: () => totalsNow}, lastMetadata: 0, lastHistorySave: 0, processMemory: 1536,
    MihomoUI: {...UI, formatTrafficTotal: (value, raw) => UI.formatTrafficTotal(value, raw, 'en-US')},
    fmtBytes: value => UI.formatBytes(value, 'en-US'), fmtCount: String,
    fmtRate: value => UI.formatBytes(value, 'en-US') + '/s',
    trafficHistory: totalHistory, drawTraffic: () => chartDraws++,
    sessionStorage: {setItem: () => historySaves++},
    ajaxGet: (url, params, done) => totalRequests.push({url, params, done})
};
vm.runInNewContext('function renderModeHint() {}\n' + totalsScript, totalsContext);
const bytesControl = totalControl('#traffic-totals-bytes');
const shownTotals = () => ['#stat-download', '#stat-upload'].map(id => totalControl(id).label);
const toggleTotals = checked => { bytesControl.checked = checked; bytesControl.handlers.change(); };
assert.equal(bytesControl.checked, false, 'Every visit starts in human-readable mode');
toggleTotals(true);
assert.deepEqual(shownTotals(), ['—', '—'], 'Toggling before the first response does not invent totals');
toggleTotals(false);
function pollTotals(downloadTotal, uploadTotal) {
    vm.runInNewContext('loadOverview();', totalsContext);
    totalRequests.at(-1).done({runtime: {downloadTotal, uploadTotal, ready: true}, controller: {alive: true}}, 'success');
    totalsNow += 2000;
}
pollTotals(1536, 1048576);
assert.deepEqual(shownTotals(), ['1.5 KiB', '1.0 MiB']);
const displayWork = () => [totalRequests.length, totalHistory.samples.length, chartDraws, historySaves,
    totalControl('#stat-memory').label, totalControl('#stat-rate-down').label, totalControl('#stat-rate-up').label];
const beforeToggle = displayWork();
toggleTotals(true);
assert.deepEqual(shownTotals(), ['1,536 B', '1,048,576 B']);
assert.deepEqual(displayWork(), beforeToggle, 'Only totals change: no polling, samples, storage, chart, memory or rate changes');
pollTotals(3584, 1049600);
assert.deepEqual(shownTotals(), ['3,584 B', '1,049,600 B'], 'Polling keeps the selected format');
assert.equal(totalControl('#stat-rate-down').label, '1.0 KiB/s');
assert.equal(totalControl('#stat-memory').label, '1.5 KiB');
toggleTotals(false);
assert.deepEqual(shownTotals(), ['3.5 KiB', '1.0 MiB'], 'Switching back uses the latest counters');
vm.runInNewContext('loadOverview();', totalsContext);
totalRequests.at(-1).done(null, 'error');
toggleTotals(true);
assert.deepEqual(shownTotals(), ['3,584 B', '1,049,600 B'], 'A failed poll retains the last received counters');
pollTotals(0, 0);
assert.deepEqual(shownTotals(), ['0 B', '0 B'], 'A core counter reset is rendered without retaining old totals');
pollTotals(undefined, null);
assert.deepEqual(shownTotals(), ['—', '—']);
toggleTotals(false);
assert.deepEqual(shownTotals(), ['—', '—']);
assert.match(indexView, /<label for="traffic-totals-bytes"[^>]*>\s*<input type="checkbox" id="traffic-totals-bytes">/);
assert(indexView.includes("lang._('Show totals in bytes')"));
console.log('Traffic totals: units, locale grouping, invalid counters, immediate toggling, polling and counter resets passed');

// Run the actual delegated copy handler. No controller, write API or browser HTML
// parser is available: copying must remain a local action on the clicked snapshot.
async function testProxyCopy() {
    assert.equal(await UI.copyText('name', undefined), false);
    assert.equal(await UI.copyText('name', {}), false);
    assert.equal(await UI.copyText('name', {writeText() { throw new Error('blocked'); }}), false);
    const copyControls = new Map();
    let focused = false, selected = false;
    function copyControl(selector) {
        if (!copyControls.has(selector)) {
            copyControls.set(selector, {
                handlers: {}, value: '', label: '', hidden: true,
                0: {focus() { focused = true; }, select() { selected = true; }},
                on(event, delegate, fn) { this.handlers[fn ? delegate : event] = fn || delegate; return this; },
                prop(key, value) { this[key] = value; return this; },
                val(value) { this.value = value; return this; },
                text(value) { this.label = value; return this; },
                empty() { this.label = ''; return this; }
            });
        }
        return copyControls.get(selector);
    }
    const clipboardWrites = [];
    let finishWrite;
    const browser = {clipboard: {writeText(text) {
        clipboardWrites.push(text);
        return new Promise(resolve => { finishWrite = resolve; });
    }}};
    const copyScript = indexView.match(/        let copying = false;[\s\S]*?(?=        let testing = false;)/)[0]
        .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
    vm.runInNewContext(copyScript, {$: copyControl, navigator: browser, MihomoUI: UI});
    const click = copyControl('#proxy-groups').handlers['.cmd-copy'];
    const firstButton = copyButtons[1];
    const pending = click.call(firstButton);
    assert.equal(copyControl('#proxy-copy-state').label, 'Copying…');
    assert.deepEqual(clipboardWrites, [names[0]], 'Clipboard starts in the user click, before yielding');
    await click.call(copyButtons[3]);
    assert.equal(clipboardWrites.length, 1, 'Pending writes cannot race with another copy');
    render(); // A poll replaces the original button while the clipboard is pending.
    finishWrite();
    await pending;
    assert.equal(copyControl('#proxy-copy-state').label, 'Copied to clipboard.');
    assert.equal(copyControl('#proxy-copy-fallback').hidden, true);
    assert.equal(copyControl('#proxy-copy-text').value, '');

    const currentButtons = groupBox.querySelectorAll('button[data-copy-text]');
    await click.call(currentButtons[0]);
    assert.equal(clipboardWrites.length, 1, 'Unavailable group selections do not write');
    browser.clipboard = {writeText() { return Promise.reject(new Error('permission denied')); }};
    await click.call(currentButtons[2]);
    assert.equal(copyControl('#proxy-copy-state').label, 'Clipboard unavailable. Copy the selected text below.');
    assert.equal(copyControl('#proxy-copy-fallback').hidden, false);
    assert.equal(copyControl('#proxy-copy-text').value, currentButtons[2].attrs['data-copy-text']);
    assert(focused && selected, 'Manual fallback focuses and selects the captured text');
    copyControl('#proxy-copy-dismiss').handlers.click();
    assert.equal(copyControl('#proxy-copy-fallback').hidden, true);
    assert.equal(copyControl('#proxy-copy-text').value, '');
    assert.equal(copyControl('#proxy-copy-state').label, '');

    browser.clipboard = undefined; // HTTP appliance or unsupported browser.
    await click.call(currentButtons.at(-1));
    assert.equal(copyControl('#proxy-copy-text').value, names.at(-1));
    browser.clipboard = {writeText: async text => clipboardWrites.push(text)};
    await click.call(currentButtons.at(-1));
    assert.equal(clipboardWrites.at(-1), names.at(-1));
    assert.equal(copyControl('#proxy-copy-fallback').hidden, true, 'Retry clears the manual fallback');
    assert.equal(copyControl('#proxy-copy-text').value, '');
    assert.equal(copyControl('#proxy-copy-state').label, 'Copied to clipboard.');
    assert.match(indexView, /id="proxy-copy-state"[^>]*role="status"/);
    assert.match(indexView, /<textarea id="proxy-copy-text"[^>]*readonly/);
    console.log('Proxy copy: exact names/selections, polling snapshots, pending writes, denied/missing clipboard and manual fallback passed');
}
testProxyCopy().catch(error => { console.error(error); process.exitCode = 1; });

// Exercise the actual mode hint, overview renderer and mode-change handler together.
const translateModeScript = script => script.replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g,
    (_, label) => JSON.stringify(label));
const modeControls = new Map(), modeWrites = [], modeTimeouts = [];
let modeRefreshes = 0, modeFailures = 0;
function modeControl(selector) {
    if (typeof selector !== 'string') { return selector; }
    if (!modeControls.has(selector)) {
        modeControls.set(selector, {
            value: '', label: '', state: {}, textWrites: 0,
            val(value) { if (arguments.length === 0) { return this.value; } this.value = value; return this; },
            text(value) { if (arguments.length === 0) { return this.label; } this.textWrites++; this.label = value; return this; },
            data(key, value) { if (arguments.length === 1) { return this.state[key]; } this.state[key] = value; return this; },
            change(handler) { this.handler = handler; }, empty() { this.label = ''; }
        });
    }
    return modeControls.get(selector);
}
const modeContext = {
    $: modeControl, Date: {now: () => 1000}, processMemory: null,
    fmtCount: String, fmtBytes: String, fmtRate: String,
    trafficHistory: {add: () => ({down: null, up: null})}, drawTraffic: () => {},
    overviewPoller: {refresh: () => { modeRefreshes++; }},
    ajaxCall: (url, data, done) => modeWrites.push({url, data, done}),
    setTimeout: fn => modeTimeouts.push(fn), actionFailed: () => { modeFailures++; },
    renderTrafficTotals() {}
};
const modeScript = indexView.match(/        function renderModeHint\(\) \{[\s\S]*?\n        \}\);/)[0];
const modeOverviewScript = indexView.match(/        function renderOverview\(data\) \{[\s\S]*?\n        \}/)[0];
vm.runInNewContext('let lastHistorySave = 1000, lastMetadata = 0;\n'
    + translateModeScript(modeScript + '\n' + modeOverviewScript), modeContext);
const modeSelect = modeControl('#mode-select'), modeHint = modeControl('#mode-hint');
const modeLabels = {
    rule: 'Rule-based: Mihomo follows matching rules to route or block traffic.',
    global: 'Global: traffic handled by Mihomo uses the GLOBAL group selection.',
    direct: 'Direct: traffic handled by Mihomo connects without a proxy.'
};
function pollMode(runtime) { modeContext.payload = {runtime, controller: {alive: true}}; vm.runInNewContext('renderOverview(payload)', modeContext); }
for (const [mode, label] of Object.entries(modeLabels)) {
    pollMode({mode});
    assert.equal(modeHint.label, label);
    const hintWrites = modeHint.textWrites;
    pollMode({ready: true});
    assert.equal(modeHint.label, label, 'Lightweight polls retain the displayed mode explanation');
    pollMode({mode});
    assert.equal(modeHint.textWrites, hintWrites, 'Unchanged polls do not repeat live-region announcements');
}
for (const mode of ['', null, 'unknown', '__proto__', '<script>']) {
    pollMode({mode});
    assert.equal(modeHint.label, '', 'Unknown modes clear old hints without rendering API text');
}
pollMode({mode: 'rule'});
modeSelect.val('global'); modeSelect.handler.call(modeSelect);
assert.equal(modeHint.label, modeLabels.global, 'A selection immediately explains the requested mode');
assert.equal(modeWrites[0].url, '/api/mihomo/dashboard/set_mode');
assert.equal(modeWrites[0].data.mode, 'global');
pollMode({mode: 'rule'});
assert.equal(modeHint.label, modeLabels.global, 'Pending changes keep selector and hint aligned');
modeWrites[0].done({status: 'failed'}, 'success');
assert.equal(modeFailures, 1, 'Hints must not suppress switch failures');
modeTimeouts.shift()(); pollMode({mode: 'rule'});
assert.equal(modeHint.label, modeLabels.rule, 'The hint follows the refreshed mode after a failed switch');
modeSelect.val('direct'); modeSelect.handler.call(modeSelect);
modeWrites[1].done({status: 'ok'}, 'success');
modeTimeouts.shift()(); pollMode({mode: 'direct'});
assert.equal(modeHint.label, modeLabels.direct);
assert.equal(modeRefreshes, 4);
assert.equal(modeWrites.length, 2, 'Rendering hints introduces no mode writes');
assert.match(indexView, /id="mode-select"[^>]*aria-describedby="mode-hint"/);
assert.match(indexView, /id="mode-hint"[^>]*role="status"/);
console.log('Mode hints: all modes, metadata gaps, unknown values, selection, failure/recovery and accessibility passed');

// Run the dashboard render path with fresh API objects and the real DOM renderer.
// Unchanged polling must retain nodes, focus and scroll without allocating DOM.
const renderGroupsScript = indexView.match(/(?:        let renderedGroups = null;\n)?        function renderGroups\(data\) \{[\s\S]*?\n        \}/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
let groupAllocations = 0;
const pollingDoc = {activeElement: null, createElement(tag) { groupAllocations++; return new DomNode(this, tag); }};
const pollingBox = pollingDoc.createElement('div');
let favoriteNotice = '', testsDisabled = false, favoriteHandler, nodeOrderHandler, collapseHandler, testGroupHandler;
const dashboardStorage = new Map();
const dashboardFavorites = new UI.ProxyFavorites(() => ({
    getItem: key => dashboardStorage.get(key) || null,
    setItem: (key, value) => dashboardStorage.set(key, value)
}));
const groupContext = vm.createContext({
    $: selector => {
        if (selector === '#proxy-node-order') {
            return {on: (event, handler) => { assert.equal(event, 'change'); nodeOrderHandler = handler; }};
        }
        if (selector instanceof DomNode) {
            return {attr: key => selector.getAttribute(key), closest: target => {
                assert.equal(target, '.content-box');
                const card = pollingBox.children[0].children.map(column => column.children[0]).find(node => node.contains(selector));
                return {find: target => {
                    assert.equal(target, '.cmd-test');
                    return {each: fn => card.querySelectorAll('button[data-name]')
                        .filter(node => node.attrs.class.includes(' cmd-test')).forEach(node => fn.call(node))};
                }};
            }};
        }
        if (selector === '#proxy-favorites-state') { return {text: value => { favoriteNotice = value; }}; }
        if (selector === '#proxy-groups .cmd-test, #proxy-groups .cmd-test-group') {
            return {prop: (key, value) => { assert.equal(key, 'disabled'); testsDisabled = value; }};
        }
        assert.equal(selector, '#proxy-groups');
        return {0: pollingBox, on: (event, target, handler) => {
            assert.equal(event, 'click');
            if (target === '.cmd-collapse-group') { collapseHandler = handler; }
            else if (target === '.cmd-test-group') { testGroupHandler = handler; }
            else { assert.equal(target, '.cmd-favorite'); favoriteHandler = handler; }
        }, html: text => {
            const placeholder = pollingDoc.createElement('placeholder');
            placeholder.textContent = text;
            pollingBox.replaceChildren(placeholder);
        }};
    },
    MihomoUI: UI, favorites: dashboardFavorites, latestGroups: null, testing: false, nodeOrder: 'config',
    delayText: value => value + ' ms', delayClass: () => 'label-success'
});
const collapseStateScript = indexView.match(/        const collapsedGroups = new Set\(\);[^\n]*/)[0];
vm.runInContext(collapseStateScript + '\n' + renderGroupsScript, groupContext);
const groupResponse = {ready: true, groups: [{name: 'Group', type: 'Selector', members: [
    {name: 'First', type: 'test', selected: true, delay: 20},
    {name: 'Second', type: 'test', selected: false, delay: 30}
]}]};
function pollGroups(response = groupResponse) {
    groupContext.response = JSON.parse(JSON.stringify(response));
    vm.runInContext('renderGroups(response);', groupContext);
}
pollGroups();
assert.deepEqual(countBadges(pollingBox).map(node => node.textContent), ['Members: 2']);
const firstRow = pollingBox.children[0];
const focusedButton = pollingBox.querySelectorAll('button[data-focus-key]')[1];
pollingDoc.activeElement = focusedButton;
pollingBox.querySelectorAll('ul[data-group]')[0].scrollTop = 123;
const initialAllocations = groupAllocations;
for (let i = 0; i < 5; i++) { pollGroups(); }
assert.equal(groupAllocations, initialAllocations, 'Unchanged API responses must allocate no DOM nodes');
assert.equal(pollingBox.children[0], firstRow);
assert.equal(pollingDoc.activeElement, focusedButton);
assert.equal(pollingBox.querySelectorAll('ul[data-group]')[0].scrollTop, 123);
for (const change of [
    () => { groupResponse.groups[0].members[0].delay = 40; },
    () => { groupResponse.groups[0].members[0].selected = false; groupResponse.groups[0].members[1].selected = true; },
    () => { groupResponse.groups[0].members.reverse(); },
    () => { groupResponse.groups[0].members.pop(); }
]) {
    const previousRow = pollingBox.children[0];
    change(); pollGroups();
    assert.notEqual(pollingBox.children[0], previousRow, 'Changed proxy data must render');
    assert.equal(countBadges(pollingBox)[0].textContent, 'Members: ' + groupResponse.groups[0].members.length);
}
// Both placeholder states invalidate the snapshot, even when recovery returns
// exactly the same groups that were displayed before the interruption.
for (const placeholder of [{ready: false}, {ready: true, groups: []}]) {
    pollGroups(placeholder);
    assert.equal(pollingBox.children[0].tagName, 'placeholder');
    assert.equal(countBadges(pollingBox).length, 0, 'Unavailable/absent groups must not retain stale counts');
    pollGroups();
    assert.equal(pollingBox.children[0].tagName, 'div', 'Recovery must replace the placeholder');
    assert.equal(countBadges(pollingBox)[0].textContent, 'Members: 1');
    const recoveredRow = pollingBox.children[0];
    pollGroups();
    assert.equal(pollingBox.children[0], recoveredRow);
}
console.log('Proxy polling skips unchanged DOM, preserves focus/scroll and renders changes/recovery: all checks passed');

// Favorites store exact decoded names, independently for groups and proxies.
let savedFavorites = null;
const favoriteStorage = {
    getItem(key) { assert.equal(key, 'mihomo.favorites.v1'); return savedFavorites; },
    setItem(key, value) { assert.equal(key, 'mihomo.favorites.v1'); savedFavorites = value; }
};
const favorites = new UI.ProxyFavorites(() => favoriteStorage);
assert.equal(favorites.has('groups', 'Group'), false);
for (const name of [...names, '__proto__', 'literal &gt;', 'same']) {
    assert.equal(favorites.toggle('proxies', name), true);
    assert(favorites.has('proxies', name));
    assert(!favorites.has('groups', name));
}
favorites.toggle('groups', 'same');
const reloadedFavorites = new UI.ProxyFavorites(() => favoriteStorage);
assert(reloadedFavorites.has('groups', 'same'));
assert(reloadedFavorites.has('proxies', 'literal &gt;'));
reloadedFavorites.toggle('proxies', 'same');
assert(!new UI.ProxyFavorites(() => favoriteStorage).has('proxies', 'same'));
assert(reloadedFavorites.has('groups', 'same'));
for (const corrupt of ['{', 'null', '42', '[]', '{"groups":{},"proxies":[null,3,{},"valid"]}']) {
    savedFavorites = corrupt;
    const recovered = new UI.ProxyFavorites(() => favoriteStorage);
    assert.equal(recovered.has('groups', 'Group'), false);
    assert.equal(recovered.toggle('groups', 'Group'), true);
}
for (const unavailable of [
    () => { throw new Error('Storage blocked'); },
    () => ({getItem() { return null; }, setItem() { throw new Error('Quota exceeded'); }})
]) {
    const temporary = new UI.ProxyFavorites(unavailable);
    assert.equal(temporary.toggle('proxies', 'temporary'), false);
    assert(temporary.has('proxies', 'temporary'), 'Storage failure still supports this page visit');
}
console.log('Favorites persistence, exact names, independent kinds and unavailable storage: all checks passed');

// Real star controls and real dashboard click handler: no controller writes or reads.
// ajaxCall/ajaxGet are deliberately absent, so accidental requests fail this test.
const favoriteClickScript = indexView.match(/        \$\('#proxy-groups'\)\.on\('click', '\.cmd-favorite',[\s\S]*?\n        \}\);/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
vm.runInContext(favoriteClickScript, groupContext);
const specialName = names[0] + ' &gt; 中文';
const favoriteResponse = {ready: true, groups: [
    {name: 'First group', members: [{name: 'First proxy', selected: true}, {name: encode(specialName)}, {name: 'Last proxy'}]},
    {name: encode(specialName), members: [{name: 'First proxy'}, {name: encode(specialName), selected: true}]},
    {name: 'Last group', members: []}
]};
const untouchedResponse = JSON.stringify(favoriteResponse);
const starButtons = () => pollingBox.querySelectorAll('button[data-kind]');
function star(kind, name, occurrence = 0) {
    const button = starButtons().filter(node => node.attrs['data-kind'] === kind && node.attrs['data-name'] === name)[occurrence];
    assert(button);
    assert.equal(button.attrs.type, 'button', 'Stars support native keyboard activation');
    pollingDoc.activeElement = button;
    favoriteHandler.call(button);
    assert.equal(pollingDoc.activeElement.attrs['data-focus-key'], button.attrs['data-focus-key']);
    assert(pollingBox.contains(pollingDoc.activeElement), 'Focus follows the reordered control');
}
const displayedGroups = () => pollingBox.querySelectorAll('ul[data-group]').map(node => node.attrs['data-group']);
const displayedMembers = () => pollingBox.querySelectorAll('ul[data-group]').map(node =>
    node.querySelectorAll('li[data-member]').map(member => member.attrs['data-member']));
pollGroups(favoriteResponse);
assert(starButtons().every(button => button.attrs['aria-pressed'] === 'false'));
star('proxies', specialName);
assert.equal(favoriteNotice, '');
assert.deepEqual(displayedMembers(), [[specialName, 'First proxy', 'Last proxy'], [specialName, 'First proxy'], []]);
assert.deepEqual(displayedGroups(), ['First group', specialName, 'Last group'], 'Proxy favorites do not star groups');
assert.equal(starButtons().filter(button => button.attrs['aria-pressed'] === 'true').length, 2, 'Shared proxies are starred everywhere');
star('groups', specialName);
assert.deepEqual(displayedGroups(), [specialName, 'First group', 'Last group']);
assert.deepEqual(countBadges(pollingBox).map(node => node.textContent), ['Members: 2', 'Members: 3', 'Members: 0'],
    'Counts stay with their groups when favorites reorder cards and members');
pollingBox.querySelectorAll('ul[data-group]')[0].scrollTop = 88;
const starredRow = pollingBox.children[0];
pollGroups(favoriteResponse);
assert.equal(pollingBox.children[0], starredRow, 'Identical polls retain favorite ordering without rendering');
groupContext.testing = true;
star('proxies', 'Last proxy');
assert.equal(testsDisabled, true, 'Starring during latency tests must retain disabled probe controls');
assert.equal(pollingBox.querySelectorAll('ul[data-group]')[0].scrollTop, 88);
groupContext.testing = false;
const selectedNames = () => pollingBox.querySelectorAll('li[data-member]').filter(node => node.attrs.class.includes(' active'))
    .map(node => node.attrs['data-member']).sort();
assert.deepEqual(selectedNames(), ['First proxy', specialName].sort(), 'Starring leaves current selection unchanged');
assert.equal(JSON.stringify(favoriteResponse), untouchedResponse, 'Display ordering must not mutate controller data');
pollGroups({ready: true, groups: [{name: 'Temporary', members: []}]});
pollGroups({ready: false});
pollGroups(favoriteResponse);
assert.deepEqual(displayedGroups(), [specialName, 'First group', 'Last group'], 'Missing groups retain preferences on recovery');
assert.deepEqual(displayedMembers(), [[specialName, 'First proxy'], [specialName, 'Last proxy', 'First proxy'], []]);
star('groups', specialName);
star('proxies', specialName, 1);
star('proxies', 'Last proxy');
assert.deepEqual(displayedGroups(), ['First group', specialName, 'Last group']);
assert.deepEqual(displayedMembers(), [['First proxy', specialName, 'Last proxy'], ['First proxy', specialName], []], 'Unstarring restores controller order');
assert(starButtons().every(button => button.attrs['aria-pressed'] === 'false'));
dashboardFavorites.storage = () => { throw new Error('Storage denied'); };
star('groups', specialName);
assert(favoriteNotice.includes('only for this page visit'));
assert.equal(displayedGroups()[0], specialName);
assert(new UI.ProxyFavorites(() => favoriteStorage).has('groups', 'Group'), 'Other storage remains independent');
console.log('Favorites dashboard clicks, stable ordering, shared proxies, polling/recovery, focus, scroll and unchanged selection: all checks passed');

// Name order is presentation-only, natural, case-insensitive and stable on ties.
const sortNames = ['Node 10', 'node 2', 'NODE 2', 'Node 1'];
const sortGroups = [{name: 'Z group', members: sortNames.map((name, i) =>
    Object.freeze({name, selected: i === 0, delay: [1, null, 500, 0][i]}))},
    {name: 'A group', members: []}];
sortGroups.forEach(group => { Object.freeze(group.members); Object.freeze(group); });
Object.freeze(sortGroups);
const renderSort = order => UI.renderProxyGroups(groupBox, sortGroups, {memberCount: 'Members: %s'}, String, () => '', null, order);
const sortedNames = () => groupBox.querySelectorAll('li[data-member]').map(node => node.attrs['data-member']);
renderSort('name-asc');
assert.deepEqual(sortedNames(), ['Node 1', 'node 2', 'NODE 2', 'Node 10']);
renderSort('name-desc');
assert.deepEqual(sortedNames(), ['Node 10', 'node 2', 'NODE 2', 'Node 1'], 'Descending keeps equal names in configuration order');
for (const mode of ['config', undefined, 'unknown']) {
    renderSort(mode);
    assert.deepEqual(sortedNames(), sortNames);
}
// Decode once before comparing, so &lt; is sorted as <, and literal &gt; stays literal.
const exactNames = ['z', '<node>', '&gt;', '中文', 'éclair', 'ÉCLAIR', 'node"quote'];
UI.renderProxyGroups(groupBox, [{name: 'Encoded', members: exactNames.map(name => ({name: encode(name)}))}],
    {memberCount: 'Members: %s'}, String, () => '', null, 'name-asc');
assert.deepEqual(sortedNames(), exactNames.slice().sort(new Intl.Collator(undefined, {numeric: true, sensitivity: 'base'}).compare));

const nodeOrderScript = indexView.match(/        \$\('#proxy-node-order'\)\.on\('change',[\s\S]*?\n        \}\);/)[0];
assert(indexView.includes('label for="proxy-node-order"'), 'Sort control has an accessible label');
for (const mode of ['config', 'name-asc', 'name-desc']) { assert(indexView.includes('option value="' + mode + '"')); }
vm.runInContext(nodeOrderScript, groupContext);
const orderBy = value => nodeOrderHandler.call({value});
groupContext.latestGroups = null;
orderBy('name-asc'); // Also safe before the first response.
const sortResponse = {ready: true, groups: sortGroups};
pollGroups(sortResponse);
assert.deepEqual(displayedGroups(), ['Z group', 'A group'], 'Name order does not reorder group cards');
assert.deepEqual(displayedMembers(), [['Node 1', 'node 2', 'NODE 2', 'Node 10'], []]);
pollingBox.querySelectorAll('ul[data-group]')[0].scrollTop = 65;
pollingDoc.activeElement = pollingBox.querySelectorAll('button[data-focus-key]')[2];
const sortFocus = pollingDoc.activeElement.attrs['data-focus-key'];
groupContext.testing = true;
orderBy('name-desc');
assert.equal(testsDisabled, true);
assert.equal(pollingBox.querySelectorAll('ul[data-group]')[0].scrollTop, 65);
assert.equal(pollingDoc.activeElement.attrs['data-focus-key'], sortFocus);
assert(pollingBox.contains(pollingDoc.activeElement));
assert.deepEqual(displayedMembers(), [['Node 10', 'node 2', 'NODE 2', 'Node 1'], []]);
assert.deepEqual(selectedNames(), ['Node 10']);
const sortedRow = pollingBox.children[0];
pollGroups(sortResponse);
assert.equal(pollingBox.children[0], sortedRow, 'Unchanged polls keep sorted DOM');
star('proxies', 'Node 1');
star('proxies', 'Node 10');
orderBy('name-asc');
assert.deepEqual(displayedMembers()[0], ['Node 1', 'Node 10', 'node 2', 'NODE 2'], 'Sort within favorites and ordinary proxies');
orderBy('config');
assert.deepEqual(displayedMembers()[0], ['Node 10', 'Node 1', 'node 2', 'NODE 2'], 'Configuration order retains favorite pinning');
star('proxies', 'Node 1');
star('proxies', 'Node 10');
assert.deepEqual(displayedMembers()[0], sortNames, 'Configuration order is fully restored');
orderBy('name-asc');
for (const placeholder of [{ready: false}, {ready: true, groups: []}]) {
    pollGroups(placeholder);
    orderBy('name-desc');
    pollGroups(sortResponse);
    assert.deepEqual(displayedMembers()[0], ['Node 10', 'node 2', 'NODE 2', 'Node 1']);
}
groupContext.testing = false;
const updatedSortResponse = JSON.parse(JSON.stringify(sortResponse));
updatedSortResponse.groups[0].members.push({name: 'Node 3'});
pollGroups(updatedSortResponse);
assert.deepEqual(displayedMembers()[0], ['Node 10', 'Node 3', 'node 2', 'NODE 2', 'Node 1'], 'New poll members use current order');
assert.deepEqual(selectedNames(), ['Node 10']);
console.log('Proxy name sorting, natural/stable order, exact names, favorites, controls, polling and recovery: all checks passed');

// Exercise the real collapse handler and renderer. No API or storage is available
// to this handler: folding cards must be a purely local display operation.
const collapseClickScript = indexView.match(/        \$\('#proxy-groups'\)\.on\('click', '\.cmd-collapse-group',[\s\S]*?\n        \}\);/)[0];
vm.runInContext(collapseClickScript, groupContext);
const foldNames = [...names, '__proto__', 'literal &gt;', 'Empty'];
const foldResponse = {ready: true, groups: foldNames.map(name => ({name: encode(name), type: 'Selector',
    members: name === 'Empty' ? [] : [{name: 'Selected', selected: true, delay: 20}, {name: 'Other', delay: 40}]}))};
const originalFoldResponse = JSON.stringify(foldResponse);
const collapseButtons = () => pollingBox.querySelectorAll('button[aria-expanded]');
const groupList = name => pollingBox.querySelectorAll('ul[data-group]').find(node => node.attrs['data-group'] === name);
function fold(name) {
    const button = collapseButtons().find(node => node.attrs['data-group'] === name);
    assert.equal(button.attrs.type, 'button', 'Collapse supports native Enter/Space activation');
    pollingDoc.activeElement = button;
    collapseHandler.call(button);
    assert(pollingBox.contains(pollingDoc.activeElement));
    assert.equal(pollingDoc.activeElement.attrs['data-focus-key'], button.attrs['data-focus-key']);
}
pollGroups(foldResponse);
assert(collapseButtons().every(button => button.attrs['aria-expanded'] === 'true'), 'All groups start expanded');
for (const name of foldNames) {
    fold(name);
    const list = groupList(name), button = pollingDoc.activeElement;
    assert.equal(list.getAttribute('hidden'), '', 'Collapsed member controls are hidden from display and keyboard navigation');
    assert.equal(button.attrs['aria-expanded'], 'false');
    assert.equal(button.attrs['aria-controls'], list.attrs.id);
    assert.equal(button.attrs['aria-label'], 'Expand group: ' + name);
    const card = pollingBox.children[0].children.map(column => column.children[0]).find(node => node.contains(list));
    assert(card.attrs.style.includes('height:auto;'), 'Collapsed cards release their fixed height');
    assert.equal(card.querySelectorAll('span[data-member-count]')[0].textContent, name === 'Empty' ? 'Members: 0' : 'Members: 2');
}
const collapsedRow = pollingBox.children[0];
pollGroups(foldResponse);
assert.equal(pollingBox.children[0], collapsedRow, 'Unchanged polls retain collapsed DOM');
assert.equal(JSON.stringify(foldResponse), originalFoldResponse);
foldResponse.groups[0].members[0].delay = 90;
foldResponse.groups[0].members[0].selected = false;
foldResponse.groups[0].members[1].selected = true;
pollGroups(foldResponse);
star('groups', foldNames[0]);
assert.equal(displayedGroups()[0], foldNames[0]);
assert(collapseButtons().every(button => button.attrs['aria-expanded'] === 'false'), 'Changed polls and favorites preserve folds by exact name');
for (const placeholder of [{ready: false}, {ready: true, groups: []}, {ready: true, groups: [{name: 'New group'}]}]) {
    pollGroups(placeholder);
    if (placeholder.groups && placeholder.groups.length) {
        assert.equal(collapseButtons()[0].attrs['aria-expanded'], 'true', 'New groups start expanded');
    }
    pollGroups(foldResponse);
    assert(collapseButtons().every(button => button.attrs['aria-expanded'] === 'false'), 'Missing groups keep their choice on recovery');
}
// The existing group-test click path must include hidden members, not just visible rows.
let foldedTestNames;
groupContext.testNodes = values => { foldedTestNames = Array.from(values); };
const testGroupScript = indexView.match(/        \$\('#proxy-groups'\)\.on\('click', '\.cmd-test-group',[\s\S]*?\n        \}\);/)[0];
vm.runInContext(testGroupScript, groupContext);
const groupTest = pollingBox.querySelectorAll('button[data-group]').find(button =>
    button.attrs.class.includes('cmd-test-group') && button.attrs['data-group'] === foldNames[0]);
testGroupHandler.call(groupTest);
assert.deepEqual(foldedTestNames, ['Selected', 'Other']);
groupContext.testing = true;
fold(foldNames[0]);
assert.equal(testsDisabled, true, 'Expanding during tests keeps probe controls disabled');
groupContext.testing = false;
assert.equal(groupList(foldNames[0]).getAttribute('hidden'), null);
assert.equal(pollingDoc.activeElement.attrs['aria-label'], 'Collapse group: ' + foldNames[0]);
assert.equal(groupList(foldNames[0]).querySelectorAll('li[data-member]')[1].attrs.class, 'list-group-item active',
    'Expanding shows the latest controller selection');
assert.equal(groupList(foldNames[1]).getAttribute('hidden'), '', 'Groups expand independently');
// A new page runs the actual initializer again; no browser persistence is used.
assert.equal(vm.runInNewContext(collapseStateScript + '\ncollapsedGroups.size;'), 0);
console.log('Group collapse: defaults, exact names, accessibility, focus, independent toggles, polling/recovery, favorites and full-group tests passed');

// Run the real connections grid setup, not a copy of the count calculation.
// No AJAX/storage APIs are supplied: counting must reuse the grid's existing data.
const connectionScript = indexView.match(/ \* 活动连接表格[\s\S]*?\*\/([\s\S]*?)(?=        function closeConnections)/)[1]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
const countFunction = indexView.match(/        function fmtCount\(value\) \{[\s\S]*?\n        \}/)[0];
const connectionEvents = {};
let connectionOptions, currentConnectionRows = [], visibleConnectionCount;
const connectionGrid = {
    on(event, handler) { connectionEvents[event] = handler; return this; },
    UIBootgrid(config) {
        connectionOptions = config.options;
        assert.equal(typeof connectionEvents['load.rs.jquery.bootgrid'], 'function',
            'Loading handler must be registered before the first grid request');
        connectionEvents['load.rs.jquery.bootgrid']();
        return this;
    },
    bootgrid(action) { assert.equal(action, 'getCurrentRows'); return currentConnectionRows; }
};
vm.runInNewContext(countFunction + connectionScript, {
    $: selector => {
        if (selector === '#grid-connections') { return connectionGrid; }
        if (selector === '#connection-visible-count') {
            return {text: value => { visibleConnectionCount = value; }};
        }
        if (selector === '[data-toggle="tooltip"]') { return {tooltip: () => {}}; }
        assert.equal(selector, '.cmd-close-connection');
        return {off() { return this; }, on() { return this; }};
    }
});
assert.equal(visibleConnectionCount, '—', 'Initial loading must not claim zero connections');
assert.match(indexView, /role="status">\{\{ lang\._\('Visible connections'\) \}\}: <span id="connection-visible-count">—<\/span>/);
function loadCountPage(rows, response = {ready: true, rows, total: 9000, rowCount: 50}) {
    connectionEvents['load.rs.jquery.bootgrid']();
    assert.equal(visibleConnectionCount, '—', 'Refresh invalidates the old count immediately');
    const before = JSON.stringify(response);
    assert.equal(connectionOptions.responseHandler(response), response, 'Preserve the framework response');
    assert.equal(JSON.stringify(response), before, 'Counting does not mutate the response');
    currentConnectionRows = rows;
    connectionEvents['loaded.rs.jquery.bootgrid']();
}
loadCountPage([{id: 'one'}, {id: 'two'}]);
assert.equal(visibleConnectionCount, '2', 'Count this page, not total matches or the page-size setting');
loadCountPage([{id: 'last'}]);
assert.equal(visibleConnectionCount, '1', 'A shorter last page/search result replaces the old count');
loadCountPage([]);
assert.equal(visibleConnectionCount, '0', 'No matches is a valid zero, not the empty-table placeholder row');
loadCountPage(Array.from({length: 1234}, (_, id) => ({id})));
assert.equal(visibleConnectionCount, (1234).toLocaleString(), 'All-rows mode uses localized number formatting');
for (const response of [{ready: false, rows: []}, {ready: true}, {ready: true, rows: null}, {}, null]) {
    loadCountPage([], response);
    assert.equal(visibleConnectionCount, 'Unavailable', 'Unavailable/malformed responses must not claim zero');
}
loadCountPage([{id: 'recovered'}]);
assert.equal(visibleConnectionCount, '1', 'A successful retry restores the count');
connectionEvents['load.rs.jquery.bootgrid'](); // Transport failure: no responseHandler callback.
assert.equal(visibleConnectionCount, '—', 'Failed requests cannot leave the previous count visible');
connectionEvents['loaded.rs.jquery.bootgrid'](); // Some grid versions also emit loaded on failure.
assert.equal(visibleConnectionCount, 'Unavailable', 'Do not count retained rows after a failed request');
loadCountPage([]);
assert.equal(visibleConnectionCount, '0', 'Recovery can also be an empty table');
console.log('Visible connection count: current page, search/empty results, refresh, locale formatting, failure and recovery passed');

// Rule-match copying preserves observed text and decodes exactly one API layer.
for (const [source, destination] of [
    ['any', 'any'], ['! 203.0.113.0/24', '! 192.0.2.0/24 port = { 53, 500, 4500 }'],
    ['2001:db8::/64 port > 1024', '2001:db8:1::/64 port 80:443'],
    ['<客户端> port = 001', '<tag> &amp; "quote" \\literal\nnext']
]) {
    assert.equal(UI.ruleMatchText({source: encode(source), destination: encode(destination)}),
        'from ' + source + ' to ' + destination);
}
for (const rule of [null, {}, {source: '', destination: 'any'}, {source: 'any'},
    {source: 'any', destination: '  '}, {source: 123, destination: 'any'}]) {
    assert.equal(UI.ruleMatchText(rule), '', 'Incomplete observations must not become invented matches');
}

// Execute the shared view, including rendering, clipboard promises and refreshes.
// The fixture never parses dynamic HTML and never talks to a real clipboard/API.
const networkView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/network_status.volt'), 'utf8');
const networkScript = networkView.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label))
    .replace(/\{\{ network_id \| json_encode \}\}/g, '"test-network"');
class NetworkNode {
    constructor(markup = '') { this.markup = markup; this.children = []; this.attrs = {}; this.label = ''; }
    text(value) { this.label = String(value); return this; }
    append(node) { this.children.push(node); return this; }
    empty() { this.children = []; this.label = ''; return this; }
    css() { return this; }
    addClass() { return this; }
    attr(key, value) { this.attrs[key] = value; return this; }
    prop(key, value) { this[key] = value; return this; }
    click(handler) { this.handler = handler; return this; }
    html() { throw new Error('Rule text must not be parsed as HTML'); }
}
async function testRuleCopy() {
    const nodes = new Map(), reads = [], copied = [], prompts = [];
    const root = {find: selector => {
        if (!nodes.has(selector)) { nodes.set(selector, new NetworkNode()); }
        return nodes.get(selector);
    }};
    const document = {getElementById: () => root, addEventListener: () => {}};
    const clipboard = {writeText: value => { copied.push(value); return Promise.resolve(); }};
    const navigator = {clipboard};
    const context = {
        document, navigator, window: {addEventListener: () => {}, prompt: (message, value) => { prompts.push({message, value}); return null; }},
        $: selector => {
            if (selector === document) { return {ready: fn => fn(), trigger: () => {}}; }
            if (selector === root || selector instanceof NetworkNode) { return selector; }
            assert(/^<(?:tr|td|strong|small|div|button)(?:\s[^<>]*)?>$/.test(selector), 'Only static markup creates nodes');
            return new NetworkNode(selector);
        },
        MihomoUI: UI, ajaxGet: (url, params, done) => reads.push({url, done})
    };
    // Use the real poller with inert timers to drive refreshes explicitly.
    context.MihomoUI = {...UI, Poller: class extends UI.Poller {
        constructor(request, interval) { super(request, interval, {hidden: () => false, schedule: () => 1, cancel: () => {}}); }
    }};
    vm.runInNewContext(networkScript, context);
    const rules = [
        {device: 'vtnet1', family: 'IPv4', direction: 'in', protocols: ['tcp'], ports: '*',
            source: encode('<clients> &amp; 中文'), destination: encode('! 192.0.2.0/24 port = { 80, 443 }'), next_hop: 'tun_mihomo 198.51.100.2'},
        {device: '', family: 'IPv6', direction: 'out', protocols: ['udp'], ports: '53',
            source: '2001:db8::/64', destination: 'any port = 53', next_hop: 'tun_mihomo 2001:db8::1'}
    ];
    const original = JSON.stringify(rules);
    const snapshot = {status: 'ok', rules_available: true, rules, interfaces: [], observed_at: 1};
    const respond = data => reads.filter(read => read.url.endsWith('/runtime_status')).at(-1).done(data, 'success');
    const buttons = () => nodes.get('.network-details-body').children.flatMap(row => row.children[3]?.children || []);
    const state = () => nodes.get('.network-copy-state').label;
    respond(snapshot);
    assert.equal(buttons().length, 2);
    const match = 'from <clients> &amp; 中文 to ! 192.0.2.0/24 port = { 80, 443 }';
    const first = buttons()[0];
    assert(first.markup.includes('type="button"'), 'Native buttons support keyboard activation');
    assert.equal(first.attrs['aria-label'], 'Copy match: ' + match);
    assert.equal(nodes.get('.network-details-body').children[0].children[3].label, '! 192.0.2.0/24 port = { 80, 443 }');
    assert(networkView.includes('class="network-copy-state text-muted" role="status" aria-live="polite"'));
    let finishCopy;
    clipboard.writeText = value => { copied.push(value); return new Promise(resolve => { finishCopy = resolve; }); };
    const pending = first.handler.call(first);
    assert.equal(first.disabled, true);
    assert.equal(state(), '', 'Do not announce success before the clipboard resolves');
    // A DNS render or new runtime snapshot cannot change the in-flight payload.
    reads.find(read => read.url.endsWith('/dns_status')).done({status: 'ok', interfaces: []}, 'success');
    assert.notEqual(buttons()[0], first);
    finishCopy(); await pending;
    assert.equal(first.disabled, false);
    assert.deepEqual(copied, [match]);
    assert.equal(state(), 'Rule match copied.');
    assert.equal(prompts.length, 0);
    for (const mode of ['reject', 'missing', 'throw']) {
        navigator.clipboard = mode === 'missing' ? undefined : {writeText: () => {
            if (mode === 'throw') { throw new Error('denied'); }
            return Promise.reject(new Error('denied'));
        }};
        await buttons()[1].handler.call(buttons()[1]);
        assert.equal(state(), 'Clipboard unavailable. Copy the rule match manually.');
        assert.equal(prompts.at(-1).value, 'from 2001:db8::/64 to any port = 53');
        assert.equal(buttons()[1].disabled, false);
    }
    assert.equal(prompts.length, 3, 'Rejection, absent API and synchronous errors all offer manual copying');
    assert.equal(JSON.stringify(rules), original, 'Copying never changes rule data');
    assert.equal(reads.length, 2, 'Copy clicks add no network requests');
    navigator.clipboard = clipboard;
    clipboard.writeText = value => { copied.push(value); return Promise.resolve(); };
    nodes.get('.network-refresh').handler();
    respond({...snapshot, rules: [{...rules[1], destination: 'any port = 853'}]});
    await buttons()[0].handler.call(buttons()[0]);
    assert.equal(copied.at(-1), 'from 2001:db8::/64 to any port = 853', 'Refreshed rows copy current conditions');
    for (const data of [{...snapshot, rules_available: false}, {...snapshot, rules: []},
        {...snapshot, rules: [{...rules[0], source: ''}]}]) {
        nodes.get('.network-refresh').handler(); respond(data);
        assert.equal(buttons().length, 0, 'Unavailable, empty or incomplete rules have no copy action');
    }
    console.log('Rule match copy: exact text, safe DOM, keyboard controls, clipboard success/fallback, refresh and read-only behavior passed');
}
testRuleCopy().catch(error => { console.error(error); process.exitCode = 1; });
