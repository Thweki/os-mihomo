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

const {filterLogLines} = require('../src/usr/local/www/js/mihomo/ui.js');
const logFixture = ['start', 'before', 'ERROR [a.*]', 'after', 'ERROR again', 'end', 'unrelated'];
assert.deepEqual(filterLogLines(logFixture, 'error', 0), {lines: [logFixture[2], logFixture[4]], matches: 2});
assert.deepEqual(filterLogLines(logFixture, 'error', 2), {lines: logFixture, matches: 2},
    'Overlapping context windows merge without duplicating lines');
assert.deepEqual(filterLogLines(logFixture, '[a.*]', 2), {lines: logFixture.slice(0, 5), matches: 1},
    'Search is literal, including regular expression punctuation');
assert.deepEqual(filterLogLines(logFixture, 'START', 2), {lines: logFixture.slice(0, 3), matches: 1});
assert.deepEqual(filterLogLines(logFixture, 'unrelated', 5), {lines: logFixture.slice(1), matches: 1});
assert.deepEqual(filterLogLines(logFixture, 'absent', 5), {lines: [], matches: 0});
assert.deepEqual(filterLogLines([], '', 5), {lines: [], matches: 0});
assert.deepEqual(filterLogLines(logFixture, '', 5), {lines: logFixture, matches: 7});
assert.deepEqual(filterLogLines(['中文', '', '<tag>&', '中文'], '中文', 2),
    {lines: ['中文', '', '<tag>&', '中文'], matches: 2}, 'Preserve blank and repeated lines and Unicode');
for (const radius of [-1, 1, 5000, NaN]) {
    assert.deepEqual(filterLogLines(logFixture, 'error', radius), filterLogLines(logFixture, 'error', 0),
        'Only supported context sizes are accepted');
}
const largeLog = Array.from({length: 3000}, (_, i) => 'line ' + i);
largeLog[2] = largeLog[2997] = 'match';
assert.deepEqual(filterLogLines(largeLog, 'match', 2),
    {lines: [...largeLog.slice(0, 5), ...largeLog.slice(-5)], matches: 2}, 'Disjoint windows keep source order');

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
control('#log-context').value = '0';
const logView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/log.volt'), 'utf8');
const logScript = logView.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
const logDownloads = [], logDownloadTypes = [], logDownloadCleanups = [], logRevokedUrls = [];
vm.runInNewContext(logScript, {
    document: fakeDocument,
    Blob: class { constructor(parts, options) { logDownloads.push(parts.join('')); logDownloadTypes.push(options.type); } },
    URL: {createObjectURL: () => 'blob:log-test', revokeObjectURL(url) { logRevokedUrls.push(url); }},
    setTimeout: (fn, ms) => { logDownloadCleanups.push({fn, ms}); },
    $: selector => selector === fakeDocument ? {ready: fn => fn()} : control(selector),
    ajaxGet: (url, params, done) => requests.push({params, done}),
    setInterval: fn => { logTimer = fn; }, MihomoUI: {logLevel, filterLogLines, decodeApiText: value => { logDecodes++; return decode(value); }}
});
assert.match(logView, /<button[^>]*id="download-filteredAct"[^>]*disabled/);
assert.equal(typeof control('#download-filteredAct').handlers.click, 'function');
assert.equal(logDownloads.length, 0, 'Loading the page must not export anything');
control('#download-filteredAct').handlers.click();
assert.equal(logDownloads.length, 0, 'Cannot download before any response');
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

control('#log-auto-refresh').checked = false;
control('#log-source').value = 'mihomo'; control('#log-source').handlers.change();
const contextData = [
    'time="2026-11-17T01:00:00Z" level=error msg="left"',
    'time="2026-11-17T01:00:00Z" level=info msg="hit"',
    'time="2026-11-17T01:00:00Z" level=error msg="hit &lt;tag&gt;"',
    'time="2026-11-17T01:00:00Z" level=error msg="right"',
    'time="2026-11-17T01:00:00Z" level=warning msg="elsewhere"',
    'time="2026-11-17T01:00:00Z" level=error msg="outside"'
];
respondLog(contextData.join('\n')+'\n');
control('#log-hide-timestamps').checked = true; control('#log-hide-timestamps').handlers.change();
levelControl.value = 'error'; levelControl.handlers.change();
control('#log-filter').value = 'hit'; control('#log-filter').handlers.input();
const beforeContext = requests.length;
control('#log-context').value = '2'; control('#log-context').handlers.change();
assert.equal(viewer.value, 'level=error msg="left"\nlevel=error msg="hit <tag>"\nlevel=error msg="right"');
assert.equal(control('#log-match-state').label, 'translated: 1 / 6 · translated: 3');
assert.equal(requests.length, beforeContext, 'Changing context while paused does not issue requests');
logTimer();
assert.equal(requests.length, beforeContext, 'Context does not resume automatic polling');
control('#downloadAct').handlers.click();
assert.equal(requests.at(-1).params.lines, 5000);
respondLog(contextData.join('\n') + '\n');
assert.equal(logDownloads.at(-1), decode(contextData.join('\n')) + '\n',
    'Context does not alter the unfiltered download bytes');
control('#log-auto-refresh').checked = true;
const contextWork = logWork();
logTimer(); respondLog(contextData.join('\n') + '\n');
assert.deepEqual(logWork(), contextWork, 'Unchanged polls do not rebuild context results');
logTimer(); requests.at(-1).done(null, 'error');
assert.equal(viewer.value, 'level=error msg="left"\nlevel=error msg="hit <tag>"\nlevel=error msg="right"',
    'An API failure preserves the context view');
control('#log-context').value = '0'; control('#log-context').handlers.change();
assert.equal(viewer.value, 'level=error msg="hit <tag>"');
assert.equal(control('#log-match-state').label, '1 / 6');
assert(logView.includes('label for="log-context"'));
console.log('Log context: literal windows, true line offsets, severity, hidden timestamps and paused requests passed');

// The local download is exactly the read-only projection of the redacted API
// response. This fixture pretends the existing server-side redactor has run.
control('#log-auto-refresh').checked = false;
const filteredDownload = control('#download-filteredAct');
const savedAnchors = [];
fakeDocument.createElement = tag => {
    assert.equal(tag, 'a');
    return {click() { savedAnchors.push({url: this.href, filename: this.download}); }};
};
const projectionInput = [
    'time="2026-11-17T01:00:00Z" level=error msg="before 中文"',
    'time="2026-11-17T01:00:00Z" level=info msg="don’t export"',
    'time="2026-11-17T01:00:00Z" level=error msg="hit &lt;tag&gt; &amp;gt; [URL redacted] token=[redacted]"',
    'time="2026-11-17T01:00:00Z" level=error msg="after"',
    'time="2026-11-17T01:00:00Z" level=warning msg="outside"'
].join('\n') + '\n';
control('#refreshAct').handlers.click(); respondLog(projectionInput);
control('#log-context').value = '2'; control('#log-context').handlers.change();
const projected = 'level=error msg="before 中文"\nlevel=error msg="hit <tag> &gt; [URL redacted] token=[redacted]"\nlevel=error msg="after"';
assert.equal(viewer.value, projected);
assert.equal(filteredDownload.disabled, false);
const noRead = requests.length, noDecode = logDecodes, noViewWrite = viewer.writes;
const wasRevoked = logRevokedUrls.length;
filteredDownload.handlers.click();
assert.equal(requests.length, noRead, 'Visible download makes no network request');
assert.equal(logDecodes, noDecode, 'No second entity decode');
assert.equal(viewer.writes, noViewWrite, 'Downloading does not change the current view');
assert.equal(logDownloads.at(-1), projected);
assert.equal(logDownloadTypes.at(-1), 'text/plain;charset=utf-8');
assert.deepEqual(savedAnchors.at(-1), {url: 'blob:log-test', filename: 'mihomo-filtered.log'});
assert.equal(logRevokedUrls.length, wasRevoked);
assert.equal(logDownloadCleanups.at(-1).ms, 1000);
logDownloadCleanups.at(-1).fn();
assert.equal(logRevokedUrls.at(-1), 'blob:log-test');

control('#log-filter').value = 'no matches'; control('#log-filter').handlers.input();
assert.equal(filteredDownload.disabled, true);
filteredDownload.handlers.click();
assert.equal(savedAnchors.length, 1, 'Cannot export a projection with no matches');
control('#log-filter').value = ''; control('#log-filter').handlers.input();
levelControl.value = 'all'; levelControl.handlers.change();
assert.equal(filteredDownload.disabled, false);
control('#refreshAct').handlers.click();
filteredDownload.handlers.click();
assert.equal(logDownloads.at(-1), viewer.value, 'Empty filters export visible text while same-source refresh is queued');
assert.equal(savedAnchors.length, 2);

control('#log-source').value = 'subscription'; control('#log-source').handlers.change();
assert.equal(viewer.value, '', 'Source change clears the snapshot before another download');
assert.equal(filteredDownload.disabled, true);
filteredDownload.handlers.click();
respondLog('stale mihomo content'); // Replaced by the queued selected source.
assert.equal(requests.at(-1).params.key, 'subscription');
assert.equal(filteredDownload.disabled, true);
respondLog('订阅日志 [URL redacted]\n');
assert.equal(filteredDownload.disabled, false);
control('#refreshAct').handlers.click(); requests.at(-1).done(null, 'error');
filteredDownload.handlers.click();
assert.equal(savedAnchors.length, 3);
assert.equal(logDownloads.at(-1), viewer.value, 'Failure retains the current source’s exportable projection');
assert.equal(logDownloads.at(-1), '订阅日志 [URL redacted]');
assert.equal(savedAnchors.at(-1).filename, 'subscription-filtered.log');

control('#downloadAct').handlers.click();
assert.equal(requests.at(-1).params.lines, 5000, 'Full download still fetches the independent 5,000-line tail');
respondLog('time="2026-11-17T01:00:00Z" level=info full-only\n');
assert.equal(logDownloads.at(-1), 'time="2026-11-17T01:00:00Z" level=info full-only\n');
assert.equal(savedAnchors.at(-1).filename, 'subscription.log');
assert.equal(viewer.value, '订阅日志 [URL redacted]', 'Full download does not replace the displayed projection');
console.log('Filtered log download: exact redacted projection, no requests, source resets and unchanged full download passed');

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
const doc = {activeElement: null, createElement(tag) { return new DomNode(this, tag); },
    createElementNS(namespace, tag) { assert.equal(namespace, 'http://www.w3.org/2000/svg'); return this.createElement(tag); }};
const groupBox = doc.createElement('div');
const names = ['name" data-unexpected="value', "single' quote", '<tag>&value', '001', '中文\\name', 'literal &gt; 😀\nnext\tline'];
const encode = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const groups = names.map(name => ({name: encode(name), now: encode(name), type: 'Selector', members: [{name: encode(name), type: 'test', selected: true, delay: 20}]}));
const latencyText = value => value === null ? 'Not tested' : value <= 0 ? 'Timeout' : value + ' ms';
const render = () => UI.renderProxyGroups(groupBox, groups, {
    testGroup: 'Test group', testNode: 'Test node', memberCount: 'Members: %s', latencyHistory: 'Recent latency, oldest first', copyName: 'Copy proxy name', copySelection: 'Copy group selection'
}, latencyText, () => 'label-success');
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

// Real renderer: bounded controller samples, independent scales, gaps and accessible values.
assert.equal(groupBox.querySelectorAll('svg[role]')[0].attrs['aria-label'], 'Recent latency, oldest first: Not tested');
groups[0].members[0].delay_history = [999, 888, 100, 200, 0, 50, 50, -1, null, 'bad', 25, 100];
groups[1].members[0].delay_history = [500];
groups[2].members[0].delay_history = [0, -1];
groups[3].members[0].delay_history = [null, NaN, Infinity, '<script>'];
render();
const charts = groupBox.querySelectorAll('svg[role]');
assert.equal(charts[0].attrs['aria-label'], 'Recent latency, oldest first: 100 ms → 200 ms → Timeout → 50 ms → 50 ms → Timeout → Not tested → Not tested → 25 ms → 100 ms');
assert.deepEqual(charts[0].querySelectorAll('polyline[points]').map(line => line.attrs.points), ['4,12 12,4', '28,16 36,16', '68,18 76,12'], 'Lines never bridge failed or unknown samples');
assert.equal(charts[0].querySelectorAll('circle[cx]').length, 6);
assert.equal(charts[0].querySelectorAll('path[d]').length, 2, 'Timeouts have crosses, not zero latency dots');
assert.equal(charts[1].querySelectorAll('circle[cx]')[0].attrs.cy, '4', 'Single samples are visible and scale independently');
assert.equal(charts[2].querySelectorAll('circle[cx]').length, 0);
assert.equal(charts[2].querySelectorAll('path[d]').length, 2);
assert.equal(charts[3].querySelectorAll('path[d]')[0].attrs.d, 'M36 12h8');
assert(!charts[3].attrs['aria-label'].includes('<script>'));
assert.equal(groupBox.querySelectorAll('span[title]').find(node => node.children.includes(charts[0])).attrs.title, charts[0].attrs['aria-label']);
assert.equal(groups[0].members[0].delay_history.length, 12, 'Rendering does not mutate API data');
console.log('Latency sparklines: bounded samples, gaps, timeouts, scale and accessible values passed');

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

// Group warnings use all reported candidates, not selection, favorites or stale alive flags.
const candidate = (name, type = 'Shadowsocks', delay = 0) => ({name: encode(name), type, delay});
const emptyGroups = [
    {name: 'Empty', members: []},
    {name: 'Failed', members: [candidate('zero'), candidate('negative', 'Vmess', -1)]},
    {name: 'Reject only', members: [candidate('block', 'Reject', 20), candidate('drop', 'RejectDrop')]},
    {name: 'Healthy', members: [candidate('failed'), candidate('working', 'Trojan', 1)]},
    {name: 'Direct', members: [candidate('custom direct', 'Direct')]},
    {name: 'Unknown', members: [candidate('untested', 'Trojan', null)]},
    {name: 'Missing'}, {name: 'Null', members: null},
    {name: encode('<Nested>&'), members: [candidate('Empty', 'Selector', 10), candidate('Failed', 'URLTest', 10)]},
    {name: 'Nested unknown', members: [candidate('Unknown', 'Selector', 0)]},
    {name: 'Missing nested', members: [candidate('not reported', 'URLTest', 0)]},
    {name: 'Missing node', members: [{name: 'absent', delay: 0, alive: false}]},
    {name: 'Cycle A', members: [candidate('Cycle B', 'Selector')]},
    {name: 'Cycle B', members: [candidate('Cycle A', 'Selector')]},
    {name: 'Exit A', members: [candidate('Exit B', 'Selector')]},
    {name: 'Exit B', members: [candidate('Exit A', 'Selector'), candidate('direct', 'Direct')]},
    {name: 'Self', members: [candidate('Self', 'Selector')]},
    {name: 'Shared', members: [candidate('Healthy', 'Selector'), candidate('Failed', 'Selector')]},
    {name: 'Pass', members: [candidate('skip', 'Pass')]},
    {name: 'Name is not type', members: [candidate('DIRECT', 'Trojan')]}
];
const warnedNames = ['Empty', 'Failed', 'Reject only', '<Nested>&', 'Cycle A', 'Cycle B', 'Self', 'Name is not type'];
const originalEmptyGroups = JSON.stringify(emptyGroups);
assert.deepEqual([...UI.emptyProxyGroups(emptyGroups)], warnedNames);
assert.deepEqual([...UI.emptyProxyGroups([...emptyGroups].reverse())].sort(), [...warnedNames].sort(), 'Graph order cannot affect warnings');
assert.equal(JSON.stringify(emptyGroups), originalEmptyGroups, 'Warnings must not mutate controller data');
for (const delay of [undefined, null, '0', NaN, Infinity]) {
    assert.equal(UI.emptyProxyGroups([{name: 'Unknown', members: [{name: 'node', type: 'Trojan', delay, alive: false}]}]).size, 0);
}
assert.equal(UI.emptyProxyGroups([{name: 'Failed', members: [{name: 'node', type: 'Trojan', delay: 0, alive: true}]}]).size, 1);
for (const type of ['Direct', 'Pass', 'PassRule', 'Rematch', 'Dns', 'Compatible', 'Unknown', 'Selector', 'URLTest', 'Fallback', 'LoadBalance', 'Relay']) {
    assert.equal(UI.emptyProxyGroups([{name: 'Context needed', members: [candidate('missing', type)]}]).size, 0,
        type + ' cannot be classified as failed using latency alone');
}
// Long provider/group chains must not overflow the stack; cycles with exits propagate too.
const deepGroups = Array.from({length: 12000}, (_, i) => ({name: String(i), members: [candidate(String(i + 1), 'Selector')]}));
deepGroups.push({name: '12000', members: []});
assert.equal(UI.emptyProxyGroups(deepGroups).size, 12001);
deepGroups[12000].members.push(candidate('exit', 'Direct'));
assert.equal(UI.emptyProxyGroups(deepGroups).size, 0);
const warningBox = doc.createElement('div');
const warningLabels = {memberCount: '成员数：%s', emptyGroup: '无可用代理', emptyGroupHint: '基于最近的延迟结果'};
UI.renderProxyGroups(warningBox, emptyGroups, warningLabels, String, () => '', null, 'config', new Set(warnedNames));
const warningBadges = box => box.querySelectorAll('span[data-empty-group]');
assert.deepEqual(warningBadges(warningBox).map(node => node.attrs['data-empty-group']), warnedNames);
warningBadges(warningBox).forEach(node => {
    assert.equal(node.textContent, warningLabels.emptyGroup);
    assert.equal(node.attrs.title, warningLabels.emptyGroupHint);
    assert(node.attrs.class.includes('label-warning'), 'Warnings have both text and theme-aware emphasis');
});
warningBox.children[0].children.forEach(column => {
    const card = column.children[0], name = card.children[1].attrs['data-group'];
    if (warnedNames.includes(name)) {
        assert.equal(card.children[1].attrs.hidden, '');
        assert.equal(warningBadges(card.children[0]).length, 1, 'Warning remains in the visible header when collapsed');
    }
});
console.log('Empty-group warnings: failures, unknowns, built-ins, nested groups, cycles, deep graphs and collapsed headers passed');

// Browser timers reject a receiver other than their global object.
const timerContext = vm.createContext({document: {hidden: false}});
vm.runInContext([
    'function setTimeout(callback, delay) { "use strict";',
    '    if (this !== undefined && this !== globalThis) { throw new TypeError("Illegal invocation"); }',
    '    return 1;',
    '}',
    'function clearTimeout(timer) { "use strict";',
    '    if (this !== undefined && this !== globalThis) { throw new TypeError("Illegal invocation"); }',
    '}'
].join('\n'), timerContext);
vm.runInContext(fs.readFileSync(require.resolve('../src/usr/local/www/js/mihomo/ui.js'), 'utf8'), timerContext);
assert.doesNotThrow(() => vm.runInContext(
    'const poller = new MihomoUI.Poller(done => done(true), 2000); poller.refresh(); poller.stop();',
    timerContext
));

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
assert.deepEqual(result, {completed: 12, total: 12, failed: 3, cancelled: false, skipped: 0});
assert.deepEqual(progress.map(item => item.completed), Array.from({length: 12}, (_, i) => i + 1));
// Stopping a batch discards only queued work and drains active requests before
// allowing another batch. Duplicate responses and repeated stops are harmless.
const pendingProbes = [], stoppedProgress = [], stoppedResults = [];
const stoppedBatch = UI.runLimited(['a', 'b', 'c', 'd', 'e', 'f'], 3,
    (name, done) => pendingProbes.push({name, done}),
    state => stoppedProgress.push(state), state => stoppedResults.push(state));
pendingProbes[0].done(true);
assert.equal(pendingProbes.length, 4);
stoppedBatch.cancel();
stoppedBatch.cancel();
assert.equal(stoppedResults.length, 0, 'Stop must wait for already submitted probes');
assert.deepEqual(stoppedProgress.at(-1), {completed: 1, total: 6, failed: 0, cancelled: true, skipped: 2});
pendingProbes[2].done(false);
pendingProbes[2].done(false);
pendingProbes[1].done(true);
assert.equal(stoppedResults.length, 0);
pendingProbes[3].done(true);
assert.equal(pendingProbes.length, 4, 'Queued probes must never be submitted after stopping');
assert.deepEqual(stoppedResults, [{completed: 4, total: 6, failed: 1, cancelled: true, skipped: 2}]);
stoppedBatch.cancel();
pendingProbes[3].done(false);
assert.equal(stoppedResults.length, 1, 'Completion fires exactly once');
for (const items of [[], ['single'], ['one', 'two', 'three', 'four']]) {
    const results = [];
    const batch = UI.runLimited(items, 3, (_, done) => done(true), () => {}, state => results.push(state));
    batch.cancel();
    assert.deepEqual(results, [{completed: items.length, total: items.length, failed: 0, cancelled: false, skipped: 0}],
        'Empty, synchronous and already finished batches complete exactly once');
}
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

// Run the real connection formatter, click binding and dialog with a strict DOM.
// No request helpers are provided: inspecting a row must remain read-only/offline.
const detailsScript = indexView.slice(indexView.indexOf('        function showConnectionDetails(row)'),
    indexView.indexOf('        function closeConnections(id)'))
    .replace(/\{\{\s*lang\._\('([^']*)'\)[\s\S]*?\}\}/g, (_, label) => JSON.stringify(label));
assert(detailsScript.includes('function showConnectionDetails'), 'Connection details must be implemented in the view');
assert.match(indexView, /data-column-id="details"[^>]*data-formatter="detailsformatter"[^>]*data-sortable="false"/);
let detailsGrid, gridLoaded, detailClick, detailsButton;
const dialogs = [];
const connectionContext = {
    document: doc,
    connectionAddressCell() {},
    MihomoUI: {...UI, element(...args) {
        const node = UI.element(...args);
        if (node.attrs.class && node.attrs.class.includes('cmd-connection-details')) { detailsButton = node; }
        return node;
    }},
    BootstrapDialog: {show: options => dialogs.push(options)},
    $: selector => {
        if (selector instanceof DomNode) { return {attr: key => selector.getAttribute(key), node: selector}; }
        if (selector === '#grid-connections') {
            return {
                UIBootgrid(options) { detailsGrid = options; return this; },
                bootgrid(action) { assert.equal(action, 'getCurrentRows'); return []; },
                on(event, callback) {
                    if (event === 'loaded.rs.jquery.bootgrid') { gridLoaded = callback; }
                    else { assert.equal(event, 'load.rs.jquery.bootgrid'); }
                    return this;
                }
            };
        }
        return {text() {}, tooltip() {}, change() {}, prop() { return this; }, each() { return this; }, off() { return this; }, on(event, callback) {
            if (selector === '.cmd-connection-details') { assert.equal(event, 'click'); detailClick = callback; }
        }};
    }
};
vm.runInNewContext(detailsScript, connectionContext);
const connection = {id: 'fixture-id', host: encode('<img src=x onerror="bad()">'), source: '192.0.2.10:1234',
    destination: '198.51.100.20:443', network: 'TCP', type: 'TUN', rule: 'DomainSuffix',
    rulePayload: encode('example.invalid & literal &gt;'), chain: encode('中文 "group" → node')};
detailsGrid.options.formatters.detailsformatter({}, connection);
const firstDetailsButton = detailsButton;
assert.equal(detailsButton.attrs.type, 'button');
assert.equal(detailsButton.attrs['aria-label'], 'Connection details');
assert.equal(JSON.parse(detailsButton.attrs['data-details']).rulePayload, connection.rulePayload);
assert(!Object.hasOwn(JSON.parse(detailsButton.attrs['data-details']), 'id'), 'Only displayed fields are copied');
gridLoaded();
detailClick.call(detailsButton);
assert.equal(dialogs[0].title, 'Connection details');
const detailFields = dialog => dialog.message.node.children[1].children;
assert.deepEqual(detailFields(dialogs[0]).filter(node => node.tagName === 'dt').map(node => node.textContent),
    ['Host', 'Source', 'Destination', 'Network', 'Type', 'Rule', 'Rule value', 'Chain']);
assert.deepEqual(detailFields(dialogs[0]).filter(node => node.tagName === 'dd').map(node => node.textContent),
    ['<img src=x onerror="bad()">', connection.source, connection.destination, 'TCP', 'TUN', 'DomainSuffix',
        'example.invalid & literal &gt;', '中文 "group" → node']);
assert(dialogs[0].message.node.children[0].textContent.includes('Snapshot'));
connection.rulePayload = 'newer value';
detailsGrid.options.formatters.detailsformatter({}, {rule: 'Match', rulePayload: '', destination: null});
gridLoaded();
detailClick.call(detailsButton);
assert.deepEqual(detailFields(dialogs[1]).filter(node => node.tagName === 'dd').map(node => node.textContent),
    ['—', '—', '—', '—', '—', 'Match', '—', '—'], 'Missing optional metadata has an explicit fallback');
detailClick.call(firstDetailsButton);
assert.equal(detailFields(dialogs[2])[13].textContent, 'example.invalid & literal &gt;',
    'Each button keeps its own snapshot, independent of later rows or refreshes');
console.log('Connection details: matched rule, destination, safe text, missing fields and per-row snapshots passed');

// Compile the complete page script too: isolated handler tests can miss broken
// boundaries or duplicate declarations introduced when features are merged.
new vm.Script(indexView.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"'), {filename: 'index.volt'});
// Run the actual connection-grid setup and change handler. The grid owns text
// search and paging; we must retain its request fields when adding the scope.
const scopeConnectionScript = indexView.match(/        \$\("#grid-connections"\)\.on\([\s\S]*?(?=        function closeConnections)/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
let connectionConfig, scopeChange, connectionScope = 'all', connectionReloads = 0;
const scopeConnectionGrid = {
    UIBootgrid(config) { connectionConfig = config; return this; },
    on() { return this; },
    bootgrid(command) { assert.equal(command, 'reload'); connectionReloads++; }
};
const processDoc = {createElement(tag) {
    const node = new DomNode(this, tag);
    // Inspect the DOM before serialization; DomNode rejects innerHTML writes.
    Object.defineProperty(node, 'outerHTML', {get: () => JSON.stringify({tag, attrs: node.attrs, text: node.textContent})});
    return node;
}};
vm.runInNewContext(scopeConnectionScript, {
    connectionAddressCell() {},
    $: selector => {
        if (selector === '#grid-connections') { return scopeConnectionGrid; }
        assert.equal(selector, '#connection-search-scope');
        return {val: () => connectionScope, change: handler => { scopeChange = handler; }};
    },
    MihomoUI: UI, document: processDoc
});
assert.equal(connectionConfig.search, '/api/mihomo/dashboard/connections');
assert(indexView.includes('<label for="connection-search-scope">'), 'Scope selector has a native accessible label');
assert(indexView.includes('<option value="all" selected>'), 'Default scope preserves broad search');
assert(indexView.includes('data-column-id="process" data-type="string" data-formatter="processformatter"'));
const searchText = '<literal>& 中文 2001:db8::1';
for (const scope of ['all', 'address', 'host', 'process']) {
    connectionScope = scope;
    const before = connectionReloads;
    scopeChange();
    assert.equal(connectionReloads, before + 1, 'Changing scope refreshes the current search');
    const request = {current: 2, rowCount: 10, sort: {start: 'desc'}, searchPhrase: searchText};
    assert.equal(connectionConfig.options.requestHandler(request), request);
    assert.deepEqual(request, {current: 2, rowCount: 10, sort: {start: 'desc'}, searchPhrase: searchText, connectionScope: scope},
        'Scope augments requests without losing search, pagination or sorting');
}
for (const [row, expected, path] of [
    [{process: 'Browser &lt;&amp;&gt;', processPath: '/opt/应用/&lt;path&gt;'}, 'Browser <&>', '/opt/应用/<path>'],
    [{processPath: '/opt/path-only'}, '/opt/path-only', '/opt/path-only'],
    [{}, '—', ''],
    [{process: 'literal &amp;gt;'}, 'literal &gt;', '']
]) {
    const rendered = JSON.parse(connectionConfig.options.formatters.processformatter({}, row));
    assert.deepEqual(rendered, {tag: 'span', attrs: {title: path}, text: expected}, 'Process names and paths use text nodes with one decode');
}
console.log('Connection search scope requests, controls and safe process rendering: all checks passed');
const overviewSource = indexView.match(/        function loadOverview\(done\) \{[\s\S]*?\n        \}/)[0];
const overviewFunction = overviewSource
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
const overviewRequests = [];
let now = 100000;
const overviewContext = {
    Date: {now: () => now}, ajaxGet: (url, data, done) => overviewRequests.push({url, data, done}),
    renderOverview: () => {}, renderClients: () => {}, drawTraffic: () => {},
    trafficHistory: {add: () => {}}, $: () => ({text: () => {}})
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
    indexView.indexOf(overviewSource) + overviewSource.length)
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
    document: {getElementById: () => null},
    $: totalControl, Date: {now: () => totalsNow}, lastMetadata: 0, lastHistorySave: 0, processMemory: 1536,
    MihomoUI: {...UI, renderConnectionClients() {}, formatTrafficTotal: (value, raw) => UI.formatTrafficTotal(value, raw, 'en-US')},
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

// Run the dashboard polling wiring and real overview renderer with controlled time.
// Pausing affects automatic statistics reads, not other panels or explicit actions.
const dashboardPollingScript = indexView.match(/        const overviewPoller =[\s\S]*?(?=\n    \}\);\n<\/script>)/)[0];
const overviewRenderScript = indexView.match(/        function renderOverview\(data\) \{[\s\S]*?\n        \}/)[0];
const translate = script => script.replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g,
    (_, label) => JSON.stringify(label));
function dashboardFixture() {
    const timers = new Map(), reads = [], instances = [], elements = new Map();
    const events = {}, pageEvents = {}, document = {hidden: false,
        addEventListener: (event, handler) => { events[event] = handler; }};
    let time = 100000, timerId = 0;
    function element(selector) {
        if (typeof selector !== 'string') { return selector; }
        if (!elements.has(selector)) {
            elements.set(selector, {label: '', value: '', click(handler) { this.handler = handler; },
                text(value) { this.label = value; return this; }, data() { return false; },
                val(value) { this.value = value; return this; }});
        }
        return elements.get(selector);
    }
    class DashboardPoller extends UI.Poller {
        constructor(request, interval) {
            super(request, interval, {hidden: () => document.hidden,
                schedule: (fn, delay) => { const id = ++timerId; timers.set(id, {fn, delay}); return id; },
                cancel: id => timers.delete(id)});
            instances.push(this);
        }
    }
    const traffic = new UI.TrafficHistory();
    const context = vm.createContext({
        MihomoUI: {...UI, Poller: DashboardPoller}, document, $: element,
        renderClients() {}, autoTestAttempted: false, autoTestCancelled: false,
        window: {addEventListener: (event, handler) => { pageEvents[event] = handler; }},
        Date: {now: () => time}, trafficHistory: traffic, processMemory: null, lastHistorySave: time, latestTotals: null, trafficTotals: new UI.TrafficTotals(), renderTrafficTotals: () => {},
        fmtCount: String, fmtBytes: String, fmtRate: String, drawTraffic: () => {},
        sessionStorage: {setItem() {}},
        ajaxGet: (url, data, done) => reads.push({url, data, done}),
        loadGroups: done => done(true), loadServiceState: done => done(true)
    });
    vm.runInContext('let lastMetadata = 0;\nfunction renderModeHint() {}\n' + translate(overviewRenderScript) + overviewFunction
        + translate(dashboardPollingScript), context);
    return {timers, reads, instances, traffic, element,
        click: () => element('#overview-pause').handler.call(element('#overview-pause')),
        advance: ms => { time += ms; },
        reply: (ready = true) => reads.at(-1).done({runtime: {ready, connections: 7,
            downloadTotal: time, uploadTotal: time}, controller: {alive: true}}, 'success'),
        fire: poller => { const timer = timers.get(poller.timer); assert(timer); timers.delete(poller.timer); timer.fn(); },
        hide: hidden => { document.hidden = hidden; events.visibilitychange(); },
        leave: () => pageEvents.pagehide()
    };
}
const dashboard = dashboardFixture();
const [statistics, proxyPolling, servicePolling] = dashboard.instances;
assert.equal(statistics.paused, false, 'New visits retain automatic polling');
assert.equal(dashboard.reads.length, 1);
dashboard.reply();
dashboard.advance(2000); dashboard.fire(statistics); dashboard.reply();
assert.notEqual(dashboard.traffic.samples.at(-1).down, null);
dashboard.click();
assert(statistics.paused);
assert(!dashboard.timers.has(statistics.timer), 'Pause cancels the next automatic read');
assert.equal(dashboard.element('#overview-pause').label, 'Resume statistics');
assert(dashboard.element('#overview-polling-state').label.includes('paused'));
assert(dashboard.timers.has(proxyPolling.timer) && dashboard.timers.has(servicePolling.timer));
dashboard.fire(proxyPolling); dashboard.fire(servicePolling);
const pausedReads = dashboard.reads.length;
dashboard.hide(true); dashboard.hide(false);
assert.equal(dashboard.reads.length, pausedReads, 'Returning to a visible tab must respect manual pause');
statistics.refresh(); dashboard.reply();
assert.equal(dashboard.reads.length, pausedReads + 1, 'Explicit action refreshes still work');
assert(!dashboard.timers.has(statistics.timer), 'An explicit read must not restart automatic polling');
dashboard.advance(1000); dashboard.click();
assert.equal(dashboard.reads.length, pausedReads + 2, 'Resume refreshes immediately');
assert.equal(dashboard.reads.at(-1).data.metadata, 1, 'Resume reloads runtime mode and version');
assert.equal(dashboard.traffic.previous, null, 'Resume resets even a short pause or manual-read baseline');
dashboard.reply();
assert.equal(dashboard.traffic.samples.at(-1).down, null, 'Traffic must not average across a pause');
assert.equal(dashboard.element('#overview-pause').label, 'Pause statistics');
assert.equal(dashboard.element('#overview-polling-state').label, '');
assert.equal(dashboard.timers.get(statistics.timer).delay, 2000);
dashboard.advance(2000); dashboard.fire(statistics);
dashboard.click(); dashboard.reply(false);
assert.equal(statistics.pending, false);
assert(!dashboard.timers.has(statistics.timer), 'An in-flight failure cannot rearm a paused poller');
dashboard.click(); dashboard.reply();
assert.equal(dashboard.timers.get(statistics.timer).delay, 2000);
dashboard.advance(2000); dashboard.fire(statistics);
const beforeRapidToggle = dashboard.reads.length;
dashboard.click(); dashboard.click();
assert.equal(dashboard.reads.length, beforeRapidToggle, 'Rapid pause/resume must not overlap requests');
dashboard.reply();
assert.equal(dashboard.timers.size, 3, 'Resume leaves exactly one timer per poller');
dashboard.click(); dashboard.hide(true); dashboard.click();
assert.equal(dashboard.reads.length, beforeRapidToggle, 'Resuming in a hidden tab defers the read');
dashboard.hide(false); dashboard.reply();
assert.equal(dashboard.reads.length, beforeRapidToggle + 1);
dashboard.fire(statistics); dashboard.click(); dashboard.leave(); dashboard.reply();
statistics.setPaused(false); statistics.refresh();
assert.equal(dashboard.timers.size, 0, 'Late responses and resume cannot revive a closed page');
const reopenedDashboard = dashboardFixture();
assert.equal(reopenedDashboard.instances[0].paused, false, 'Pause is not persisted across visits');
reopenedDashboard.leave();
assert(indexView.includes('id="overview-pause" aria-describedby="overview-polling-state"'));
assert(indexView.includes('id="overview-polling-state" class="text-muted" role="status" aria-live="polite"'));
console.log('Dashboard pause/resume: timers, visibility, actions, in-flight reads, traffic gaps and teardown passed');

// Run the actual opt-in initializer: storage and DOM are boundaries, not copied logic.
const compactInitializer = indexView.match(/        function initCompactOverview\(\) \{[\s\S]*?\n        \}/)[0];
function compactPage(saved, failure) {
    const values = new Map(saved === undefined ? [] : [['mihomo.overview.compact.v1', saved]]);
    const writes = [], classes = new Set();
    let change, resizes = 0;
    const toggle = {checked: false, addEventListener(event, handler) {
        assert.equal(event, 'change'); change = handler;
    }};
    const root = {classList: {toggle(name, enabled) {
        assert.equal(name, 'mihomo-compact');
        if (enabled) { classes.add(name); } else { classes.delete(name); }
    }}};
    const storage = {
        getItem(key) { assert.equal(key, 'mihomo.overview.compact.v1'); return values.get(key) ?? null; },
        setItem(key, value) { writes.push(['set', key, value]); values.set(key, value); },
        removeItem(key) { writes.push(['remove', key]); values.delete(key); }
    };
    if (failure && failure !== 'access') {
        storage[failure] = () => { throw new Error('Storage unavailable'); };
    }
    const context = {
        window: {get localStorage() {
            if (failure === 'access') { throw new Error('Storage blocked'); }
            return storage;
        }},
        document: {getElementById(id) {
            assert(['compact-overview', 'mihomo-overview'].includes(id));
            return id === 'compact-overview' ? toggle : root;
        }},
        gTrafficChart: null
    };
    vm.runInNewContext(compactInitializer + '\ninitCompactOverview();', context);
    assert.equal(writes.length, 0, 'Opening the page must not write a preference');
    context.gTrafficChart = {resize() { resizes++; }};
    return {toggle, values, writes, classes, resizes: () => resizes,
        change(enabled) { toggle.checked = enabled; change(); }};
}
for (const saved of [undefined, '', '0', 'false', 'true', 'yes', '{}']) {
    const page = compactPage(saved);
    assert.equal(page.toggle.checked, false, 'Only an explicit opt-in enables the experiment');
    assert.equal(page.classes.size, 0);
}
const compact = compactPage();
compact.change(true);
assert.equal(compact.toggle.checked, true);
assert(compact.classes.has('mihomo-compact'));
assert.deepEqual(compact.writes, [['set', 'mihomo.overview.compact.v1', '1']]);
const restoredCompact = compactPage(compact.values.get('mihomo.overview.compact.v1'));
assert.equal(restoredCompact.toggle.checked, true);
assert(restoredCompact.classes.has('mihomo-compact'));
compact.change(false);
assert.equal(compact.classes.size, 0);
assert.equal(compact.values.size, 0, 'Disabling removes the preference instead of storing false');
assert.deepEqual(compact.writes.at(-1), ['remove', 'mihomo.overview.compact.v1']);
assert.equal(compact.resizes(), 2, 'Both directions resize the existing chart');
assert.equal(compactPage(compact.values.get('mihomo.overview.compact.v1')).toggle.checked, false);
for (const failure of ['access', 'getItem', 'setItem', 'removeItem']) {
    const page = compactPage(undefined, failure);
    page.change(true);
    assert(page.classes.has('mihomo-compact'), failure + ' must not prevent enabling');
    page.change(false);
    assert.equal(page.classes.size, 0, failure + ' must not prevent disabling');
    assert.equal(page.resizes(), 2);
}
// The native checkbox is unchecked, labeled and wired; every CSS rule is opt-in.
assert(indexView.includes('        initCompactOverview();'));
assert.match(indexView, /<div id="mihomo-overview">/);
assert.match(indexView, /<label for="compact-overview"/);
const compactInput = indexView.match(/<input[^>]*id="compact-overview"[^>]*>/)[0];
assert(compactInput.includes('type="checkbox"') && !compactInput.includes('checked'));
assert(compactInput.includes('aria-controls="mihomo-overview"'));
const compactCSS = indexView.match(/<style id="mihomo-compact-style">([\s\S]*?)<\/style>/)[1].replace(/\/\*[\s\S]*?\*\//g, '');
const selectors = Array.from(compactCSS.matchAll(/([^{}]+)\{/g), match => match[1].trim())
    .filter(selector => !selector.startsWith('@media'));
assert(selectors.length > 0);
assert(selectors.every(selector => selector.split(',').every(part => part.trim().startsWith('#mihomo-overview.mihomo-compact '))));
assert.match(compactCSS, /#traffic-chart-container\s*\{ height: 140px !important;/);
assert.match(indexView, /id="traffic-chart-container" style="height: 200px;"/);
assert.match(compactCSS, /@media \(min-width: 1200px\)[\s\S]*width: 33\.333333%;/);
assert(!/display:\s*none|visibility:\s*hidden/.test(compactCSS), 'Compact mode must not hide controls or status');
console.log('Experimental compact overview: opt-in, persistence/removal, storage failures, chart resize and scoped styles passed');
assert(compactCSS.includes('.content-box:has(> ul[data-group]:not([hidden]))'), 'Collapsed groups retain auto height');

// Traffic measurement uses the real overview handlers and request/render path.
// No write API is provided: resetting must work with view-only access.
const totals = new UI.TrafficTotals();
assert.equal(totals.reset(), false);
assert.equal(totals.values(), null);
totals.update(100, 50, true);
assert.deepEqual(totals.values(), {download: 100, upload: 50});
assert.equal(totals.reset(), true);
assert.deepEqual(totals.values(), {download: 0, upload: 0});
for (const invalid of [null, undefined, NaN, Infinity, -1, 0.5, Number.MAX_SAFE_INTEGER + 1, '123', false]) {
    for (const pair of [[invalid, 60], [200, invalid]]) {
        totals.update(...pair, true);
        assert.equal(totals.values(), null, 'Invalid counters cannot create a measurement');
        assert.equal(totals.reset(), false, 'Invalid samples cannot replace the baseline');
    }
}
totals.update(300, 150, true);
assert.deepEqual(totals.values(), {download: 200, upload: 100}, 'Recovery preserves the baseline');
totals.update(250, 160, true);
assert.equal(totals.baseline, null, 'A decrease above the baseline still ends the measurement');
assert.equal(totals.restarted, true);
assert.deepEqual(totals.values(), {download: 250, upload: 160});
totals.reset();
totals.update(300, 159, true);
assert.equal(totals.baseline, null, 'Either counter decreasing ends both measurements');
totals.update(0, 0, true);
assert.equal(totals.reset(), true, 'Zero counters are valid');
totals.update(2 ** 40, 2 ** 39, true);
assert.deepEqual(totals.values(), {download: 2 ** 40, upload: 2 ** 39}, 'No 32-bit truncation');

const trafficMeasurementScript = ('let gTrafficChart = null;\n' + indexView.slice(indexView.indexOf('        let processMemory = null;'),
    indexView.indexOf('        const favorites =')))
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
function trafficPage() {
    const elements = new Map(), reads = [];
    let now = 100000;
    const element = selector => {
        if (!elements.has(selector)) {
            elements.set(selector, {label: '', handlers: {}, disabled: true, writes: 0,
                text(value) { this.label = value; this.writes++; return this; },
                prop(key, value) { if (arguments.length === 1) { return this[key]; } this[key] = value; return this; },
                on(event, handler) { this.handlers[event] = handler; return this; },
                data() { return false; }, val() { return this; }});
        }
        return elements.get(selector);
    };
    const context = vm.createContext({
        MihomoUI: {...UI, renderConnectionClients() {}, formatTrafficTotal: (value, raw) => UI.formatTrafficTotal(value, raw, 'en-US')},
        $: element, document: {getElementById: () => null}, Date: {now: () => now},
        fmtBytes: value => UI.formatBytes(value, 'en-US'), fmtCount: String,
        fmtRate: value => UI.formatBytes(value, 'en-US') + '/s',
        sessionStorage: {getItem() { throw new Error('Storage denied'); }, setItem() { throw new Error('Storage denied'); }},
        ajaxGet: (url, params, done) => { assert.equal(url, '/api/mihomo/dashboard/overview'); reads.push(done); }
    });
    vm.runInContext('function renderModeHint() {}\n' + trafficMeasurementScript, context);
    return {element, context, reads,
        request() { now += 2000; vm.runInContext('loadOverview();', context); },
        respond(download, upload, ready = true, alive = true) {
            reads.shift()({runtime: {downloadTotal: download, uploadTotal: upload, ready}, controller: {alive}}, 'success');
        },
        click(selector) { element(selector).handlers.click(); },
        values() { return ['#stat-download', '#stat-upload'].map(id => element(id).label); }
    };
}
const traffic = trafficPage();
traffic.click('#reset-traffic-totals');
assert.equal(traffic.element('#reset-traffic-totals').disabled, true);
assert.deepEqual(traffic.values(), ['—', '—']);
traffic.request(); traffic.respond(1000, 500);
assert.deepEqual(traffic.values(), ['1,000.0 B', '500.0 B']);
assert.equal(traffic.element('#reset-traffic-totals').disabled, false);
traffic.request(); // A response is in flight while the latest displayed sample is reset.
const rawHistory = vm.runInContext('JSON.stringify(trafficHistory)', traffic.context);
traffic.click('#reset-traffic-totals');
assert.deepEqual(traffic.values(), ['0.0 B', '0.0 B']);
assert.equal(traffic.element('#traffic-totals-note').label, 'Since reset (this page)');
const byteToggle = traffic.element('#traffic-totals-bytes');
byteToggle.checked = true; byteToggle.handlers.change();
assert.deepEqual(traffic.values(), ['0 B', '0 B'], 'Reset totals also honor raw bytes mode');
byteToggle.checked = false; byteToggle.handlers.change();
assert.equal(vm.runInContext('JSON.stringify(trafficHistory)', traffic.context), rawHistory, 'Reset preserves chart and rate history');
assert.equal(traffic.reads.length, 1, 'Reset makes no request');
const statusWrites = traffic.element('#traffic-totals-note').writes;
traffic.respond(1200, 600);
assert.equal(traffic.element('#traffic-totals-note').writes, statusWrites, 'Unchanged status is not reannounced every poll');
assert.deepEqual(traffic.values(), ['200.0 B', '100.0 B']);
assert.equal(traffic.element('#stat-rate-down').label, '100.0 B/s', 'Rates still use raw counters');
traffic.click('#reset-traffic-totals');
traffic.request(); traffic.respond(1300, 650);
assert.deepEqual(traffic.values(), ['100.0 B', '50.0 B'], 'Repeated reset uses the latest sample');
traffic.request(); traffic.reads.shift()(null, 'error');
assert.deepEqual(traffic.values(), ['—', '—']);
assert.equal(traffic.element('#reset-traffic-totals').disabled, true);
traffic.click('#reset-traffic-totals'); // Guard even if invoked programmatically.
traffic.request(); traffic.respond(1400, 700);
assert.deepEqual(traffic.values(), ['200.0 B', '100.0 B']);
for (const state of [[false, true], [true, false]]) {
    traffic.request(); traffic.respond(0, 0, ...state);
    assert.equal(traffic.element('#reset-traffic-totals').disabled, true);
    assert.deepEqual(traffic.values(), ['—', '—']);
}
traffic.request(); traffic.respond(1500, 750);
assert.deepEqual(traffic.values(), ['300.0 B', '150.0 B'], 'Unavailable controller zeros do not erase baseline');
traffic.request(); traffic.respond(1400, 800);
assert.equal(traffic.element('#traffic-totals-note').label, 'Core counters decreased; showing core totals.');
assert.deepEqual(traffic.values(), ['1.4 KiB', '800.0 B']);
assert.equal(traffic.element('#restore-traffic-totals').disabled, true);
traffic.click('#reset-traffic-totals');
traffic.request(); traffic.respond(1500, 900);
traffic.click('#restore-traffic-totals');
assert.deepEqual(traffic.values(), ['1.5 KiB', '900.0 B']);
assert.equal(traffic.element('#traffic-totals-note').label, 'Core totals');
traffic.click('#reset-traffic-totals');
const reloadedTraffic = trafficPage();
reloadedTraffic.request(); reloadedTraffic.respond(1500, 900);
assert.deepEqual(reloadedTraffic.values(), ['1.5 KiB', '900.0 B'], 'Another page/reload starts with core totals');
assert.deepEqual(traffic.values(), ['0.0 B', '0.0 B'], 'Page measurement remains independent');
for (const id of ['reset-traffic-totals', 'restore-traffic-totals']) {
    assert.match(indexView, new RegExp('<button type="button" id="' + id + '"[^>]* disabled'), 'Native keyboard-accessible controls start disabled');
}
console.log('Traffic totals: reset, restore, polling, failures, counter decreases, raw rates and page isolation passed');
// Carry the reviewed network revision through the two distinct apply requests.
const routingView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/routing.volt'), 'utf8');
const collectNetworkPlan = routingView.match(/        function collectPlan\(done\) \{[\s\S]*?\n        \}/)[0];
const networkApplyHandler = routingView.match(/        \$\('#applyPolicyAct'\)\.click\(function \(\) \{[\s\S]*?\n        \}\);/)[0]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
const networkRequests = [], networkDialogs = [];
let applyNetworkClick;
const networkContext = {
    $: selector => ({click: fn => { applyNetworkClick = fn; }, css() { return this; }, text() { return this; }}),
    ajaxGet: (url, data, done) => networkRequests.push({url, data, done}),
    ajaxCall: (url, data, done) => networkRequests.push({url, data, done}),
    BootstrapDialog: {show: data => networkDialogs.push(data)},
    planText: () => '', dialog: () => {}, decode: text => text, loadState: () => {}
};
vm.runInNewContext('let lastPlan;\n' + collectNetworkPlan + '\n' + networkApplyHandler, networkContext);
applyNetworkClick();
networkRequests[0].done({version: 'yaml-preview'}, 'success');
networkRequests[1].done({status: 'ok', version: 'reviewed-network'}, 'success');
networkDialogs[0].buttons[1].action({close: () => {}});
assert.equal(networkRequests[2].data.version, 'yaml-preview');
networkRequests[2].done({status: 'ok'});
assert.equal(networkRequests[3].url, '/api/mihomo/routing/netapply');
assert.equal(networkRequests[3].data.version, 'reviewed-network', 'Network apply uses the reviewed revision');
applyNetworkClick();
networkRequests[4].done({version: 'new-yaml-preview'}, 'success');
networkRequests[5].done({status: 'failed', message: 'Configuration changed'}, 'success');
assert.equal(networkDialogs.length, 1, 'A conflicting network plan cannot offer apply');
console.log('Network plan/apply revision handoff and conflicting preview: all checks passed');
// B7: render the real routing state labels, including disabled and unreadable PF.
const stateRenderer = routingView.match(/function stateText\(row\) \{[\s\S]*?\n        \}/)[0]
    .replace(/\{\{\s*lang\._\('([^']+)'\)\s*\|\s*json_encode\s*\}\}/g, (_, value) => JSON.stringify(value));
const renderState = vm.runInNewContext('(' + stateRenderer + ')');
for (const [state, label] of Object.entries({active: 'PF rule observed', pending: 'Not confirmed',
    disabled: 'Disabled', unknown: 'Unavailable', inactive: 'TUN off', manual: 'Manual'})) {
    assert.equal(renderState({state}), label, 'Binding state must not imply verified traffic: ' + state);
}
console.log('B7 routing labels distinguish observed PF, pending, unavailable and disabled bindings: passed');
// Run the subscription page with delayed saves. An acknowledgement belongs to
// the submitted snapshot, even when the user has already typed the next edit.
const subscriptionControls = new Map(), subscriptionReads = [], subscriptionWrites = [], subscriptionPollers = [];
const subscriptionDocument = {addEventListener() {}};
function subscriptionControl(selector) {
    if (typeof selector === 'object') { return selector; }
    if (!subscriptionControls.has(selector)) {
        subscriptionControls.set(selector, {
            value: '', handlers: {},
            val(value) { if (value === undefined) { return this.value; } this.value = value; return this; },
            prop(key, value) { if (value === undefined) { return this[key]; } this[key] = value; return this; },
            on(event, fn) { this.handlers[event] = fn; return this; },
            click(fn) { return this.on('click', fn); },
            text() { return this; }, css() { return this; }, show() { return this; }
        });
    }
    return subscriptionControls.get(selector);
}
vm.runInNewContext(subscriptionView.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"'), {
    document: subscriptionDocument, window: {addEventListener() {}},
    $: selector => selector === subscriptionDocument ? {ready: fn => fn()} : subscriptionControl(selector),
    ajaxGet: (url, data, done) => subscriptionReads.push({url, data, done}),
    ajaxCall: (url, data, done) => subscriptionWrites.push({url, data, done}),
    BootstrapDialog: {show() {}}, setTimeout() {},
    MihomoUI: {...UI, Poller: class {
        constructor(request) { subscriptionPollers.push(request); }
        refresh() {} stop() {} visibilityChanged() {}
    }}
});
const subscriptionUrl = subscriptionControl('[id="mihomo.subscription.url"]');
const subscriptionSecret = subscriptionControl('[id="mihomo.subscription.secret"]');
const subscriptionSave = subscriptionControl('#saveAct');
const subscriptionRun = subscriptionControl('#runAct');
const envFile = '/usr/local/etc/mihomo/sub/env';
function editSubscription(url, secret) {
    subscriptionUrl.val(url); subscriptionSecret.val(secret);
    subscriptionControl('[id="mihomo.subscription.url"], [id="mihomo.subscription.secret"]').handlers['input change']();
}
function pollSubscription() {
    subscriptionPollers[0]();
    subscriptionReads.at(-1).done({status: 'ok', subscription: {state: 'idle'}}, 'success');
}
subscriptionReads[0].done({url: 'https://example.invalid/original', secret: 'example-original',
    version: 'original', envFile, scriptAvailable: true}, 'success');
pollSubscription();
editSubscription('https://example.invalid/submitted', 'example-submitted');
subscriptionSave.handlers.click.call(subscriptionSave);
assert.equal(subscriptionWrites[0].data.version, 'original');
editSubscription('https://example.invalid/newer', 'example-newer');
const readsBeforeSave = subscriptionReads.length;
subscriptionWrites[0].done({status: 'ok', versions: {[envFile]: 'saved-revision'}}, 'success');
// Complete any reload the old implementation issued, reproducing the lost edit.
if (subscriptionReads.length > readsBeforeSave) {
    subscriptionReads.at(-1).done({url: 'https://example.invalid/submitted', secret: 'example-submitted',
        version: 'saved-revision', envFile, scriptAvailable: true}, 'success');
}
assert.equal(subscriptionUrl.val(), 'https://example.invalid/newer', 'Save acknowledgement must preserve newer URL edits');
assert.equal(subscriptionSecret.val(), 'example-newer', 'Save acknowledgement must preserve newer secret edits');
assert.equal(subscriptionReads.length, readsBeforeSave, 'Save uses its committed revision without reloading another writer\'s state');
assert.equal(subscriptionSave.disabled, false, 'Newer edits remain available to save');
assert.equal(subscriptionRun.disabled, true, 'Unsaved edits prevent a subscription run');
subscriptionSave.handlers.click.call(subscriptionSave);
assert.equal(subscriptionWrites[1].data.version, 'saved-revision', 'Next save uses the acknowledged revision');
pollSubscription();
editSubscription('https://example.invalid/newer', 'example-newer');
assert.equal(subscriptionSave.disabled, true, 'Polling and input events cannot enable a pending save');
subscriptionSave.handlers.click.call(subscriptionSave);
assert.equal(subscriptionWrites.length, 2, 'Only one save may be pending');
subscriptionWrites[1].done({status: 'failed', code: 'conflict'}, 'success');
assert.equal(subscriptionUrl.val(), 'https://example.invalid/newer', 'Conflicts preserve unsaved input');
assert.equal(subscriptionSave.disabled, false);
assert.equal(subscriptionRun.disabled, true);
subscriptionSave.handlers.click.call(subscriptionSave);
assert.equal(subscriptionWrites[2].data.version, 'saved-revision', 'Failure cannot advance the saved revision');
subscriptionWrites[2].done(null, 'error');
assert.equal(subscriptionSave.disabled, false, 'Transport failure permits retry');
editSubscription(' https://example.invalid/final ', ' example-final ');
subscriptionSave.handlers.click.call(subscriptionSave);
subscriptionWrites[3].done({status: 'ok', versions: {[envFile]: 'final-revision'}}, 'success');
assert.equal(subscriptionUrl.val(), 'https://example.invalid/final', 'Unchanged input reflects backend trimming');
assert.equal(subscriptionSecret.val(), 'example-final');
assert.equal(subscriptionSave.disabled, true, 'Acknowledged input is clean');
assert.equal(subscriptionRun.disabled, false, 'Clean saved settings allow a subscription run');
console.log('Subscription delayed saves, edit preservation, revision handoff and failures: all checks passed');
// Comparison exports contain the complete observed snapshot, never arbitrary API fields.
const comparisonTime = '2026-11-15T12:34:56.000Z';
const comparisonData = {status: 'ok', runtime: false, content: 'excluded raw configuration', rows: [
    {key: 'mode', label: '模式 &amp; &lt;mode&gt;', group: 'general', model: 'rule', file: 'global', runtime: '', state: 'differs', secret: false, runtime_only: false, extra: 'excluded row field'},
    {key: 'tun.enable', model: 'true', file: 'true', runtime: '', state: 'match', managed: false},
    {key: 'dns.enable', model: 'true', file: '(not set in the file)', runtime: '', state: 'missing'},
    {key: 'mixed-port', model: '', file: '', runtime: '', state: 'na', runtime_only: true},
    {key: 'secret', model: 'synthetic-model-value', file: 'synthetic-file-value', runtime: 'synthetic-runtime-value', state: 'differs'},
    {key: 'future-sensitive-field', secret: true, model: 'synthetic-other-value'}
]};
const comparisonReport = UI.comparisonReport(comparisonData, comparisonTime);
assert.equal(comparisonReport.schema_version, 1);
assert.equal(comparisonReport.collected_at, comparisonTime);
assert.equal(comparisonReport.runtime_available, false, 'Offline snapshots remain exportable');
assert.equal(comparisonReport.rows.length, 6, 'Include matching, missing and runtime-only rows');
assert.equal(comparisonReport.rows[0].label, '模式 & <mode>');
assert.equal(comparisonReport.rows[0].file, 'global');
assert.equal(comparisonReport.rows[1].managed, false);
assert.equal(comparisonReport.rows[3].runtime_only, true);
for (const row of comparisonReport.rows.slice(4)) {
    assert.equal(row.secret, true);
    assert.equal(row.model, null);
    assert.equal(row.file, null);
    assert.equal(row.runtime, null);
}
assert(!JSON.stringify(comparisonReport).includes('synthetic-'), 'Sensitive row values must be omitted');
assert(!JSON.stringify(comparisonReport).includes('excluded'), 'Only explicit report fields are exported');
assert.equal(comparisonData.rows[4].model, 'synthetic-model-value', 'Export must not mutate cached API data');
comparisonData.rows[0].file = 'changed later';
assert.equal(comparisonReport.rows[0].file, 'global', 'Export is a snapshot');
assert.equal(UI.comparisonReport({...comparisonData, runtime: true}, comparisonTime).runtime_available, true);
for (const invalid of [null, {}, {status: 'failed', rows: []}, {status: 'ok'}, {status: 'ok', rows: {}}]) {
    assert.equal(UI.comparisonReport(invalid, comparisonTime), null, 'Failed/malformed responses cannot be exported');
}
assert.equal(UI.comparisonReport({status: 'ok', rows: [], runtime: false}, comparisonTime).rows.length, 0);

// Run the real view's load/filter/download handlers with browser APIs at the boundary.
const comparisonScript = settingsView.slice(settingsView.indexOf('        function loadCompare()'),
    settingsView.indexOf("        if (window.location.hash === '#compare')"))
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
const exportControls = new Map(), exportRequests = [], downloads = [], exportBlobs = [], revoked = [], cleanup = [];
function exportControl(selector) {
    if (!exportControls.has(selector)) {
        exportControls.set(selector, {
            handlers: {}, disabled: false,
            prop(key, value) { if (value === undefined) { return this[key]; } this[key] = value; return this; },
            find() { return this; }, addClass() { return this; }, removeClass() { return this; }, html() { return this; },
            click(fn) { this.handlers.click = fn; return this; }, change(fn) { this.handlers.change = fn; return this; },
            on(event, fn) { this.handlers[event] = fn; return this; }
        });
    }
    return exportControls.get(selector);
}
const exportContext = {
    $: exportControl, MihomoUI: UI,
    Date: class extends Date { constructor() { super(comparisonTime); } },
    ajaxGet: (url, params, done) => exportRequests.push({url, done}),
    Blob: class { constructor(parts, options) { this.parts = parts; this.type = options.type; } },
    URL: {createObjectURL(blob) { exportBlobs.push(blob); return 'blob:comparison-' + exportBlobs.length; },
        revokeObjectURL(url) { revoked.push(url); }},
    document: {
        body: {appendChild(link) { link.attached = true; }},
        createElement(tag) { assert.equal(tag, 'a'); return {
            click() { assert(this.attached); downloads.push(this); }, remove() { this.attached = false; }
        }; }
    },
    setTimeout: fn => cleanup.push(fn)
};
vm.runInNewContext(`let compareExport = null, compareLoading = false, compareCache = null, compareCacheStatus = 'success';
    function renderCompare(data, status) { compareCache = data; compareCacheStatus = status; }
    ${comparisonScript}`, exportContext);
const exportButton = exportControl('#compare-export');
assert.match(settingsView, /id="compare-export"[^>]* disabled/, 'Download is disabled before the first read');
exportButton.handlers.click();
assert.equal(downloads.length, 0);
exportControl('#compare-refresh').handlers.click();
exportControl('#compareTab').handlers['shown.bs.tab']();
assert.equal(exportRequests.length, 1, 'Overlapping reads do not replace a newer snapshot');
assert.equal(exportRequests[0].url, '/api/mihomo/settings/inspect');
assert.equal(exportButton.disabled, true);
exportRequests[0].done(comparisonData, 'success');
assert.equal(exportButton.disabled, false);
exportControl('#compare-diff-only').checked = true;
exportControl('#compare-diff-only').handlers.change();
exportButton.handlers.click();
assert.equal(exportRequests.length, 1, 'Export does not fetch raw YAML or refresh the snapshot');
assert.equal(exportBlobs[0].type, 'application/json;charset=utf-8');
const downloadedReport = JSON.parse(exportBlobs[0].parts.join(''));
assert.equal(downloadedReport.rows.length, 6, 'Table filtering does not truncate the report');
assert.equal(downloadedReport.collected_at, comparisonTime);
assert.equal(downloads[0].download, 'mihomo-comparison-2026-11-15T12-34-56-000Z.json');
assert.equal(downloads[0].attached, false);
cleanup.forEach(fn => fn());
assert.deepEqual(revoked, ['blob:comparison-1']);
for (const [data, status] of [[comparisonData, 'error'], [{status: 'failed'}, 'success'], [null, 'success']]) {
    exportControl('#compare-refresh').handlers.click();
    assert.equal(exportButton.disabled, true);
    exportButton.handlers.click();
    exportRequests.at(-1).done(data, status);
    assert.equal(exportButton.disabled, true);
    exportButton.handlers.click();
    assert.equal(downloads.length, 1, 'Pending/failed reads cannot export stale or error data');
}
exportControl('#compare-refresh').handlers.click();
exportRequests.at(-1).done({...comparisonData, runtime: true}, 'success');
assert.equal(exportButton.disabled, false, 'Successful refresh re-enables export');
console.log('Comparison JSON schema, secret omission, snapshot download, filtering and read failures: all checks passed');

// Run the overview's real proxy controls, request callbacks and lifecycle handlers.
// Fake transport keeps probes pending so cancellation and concurrency are observable.
const proxyScript = indexView.match(/        function renderGroups[\s\S]*?(?=        \/\* ---)/)[0];
const lifecycleScript = indexView.slice(indexView.indexOf('        const overviewPoller ='), indexView.lastIndexOf('    });'));
function autoTestPage(saved, storageBlocked = false) {
    const elements = new Map(), reads = [], probes = [], events = {}, storage = new Map();
    if (saved !== undefined) { storage.set('mihomo.autoTest.v1', saved); }
    const pageDocument = {hidden: false, addEventListener: (name, fn) => { events[name] = fn; }, createTextNode: text => text};
    function element(selector) {
        if (!elements.has(selector)) {
            elements.set(selector, {
                checked: false, disabled: false, label: '', handlers: {},
                click(handler) { this.handlers.click = handler; return this; },
                empty() { this.label = ''; return this; },
                prop(key, value) { if (value === undefined) { return this[key]; } this[key] = value; return this; },
                on(event, selectorOrFn, fn) { this.handlers[fn ? event + ':' + selectorOrFn : event] = fn || selectorOrFn; return this; },
                text(value) { this.label = value; return this; }, append(text) { this.label += text; return this; },
                attr(key) { return this[key]; }
            });
        }
        return elements.get(selector);
    }
    const context = vm.createContext({
        MihomoUI: UI, document: pageDocument, window: {addEventListener: (name, fn) => { events[name] = fn; }},
        $: selector => typeof selector === 'string' ? element(selector) : selector,
        sessionStorage: {
            getItem(key) { if (storageBlocked) { throw new Error('blocked'); } return storage.get(key); },
            setItem(key, value) { if (storageBlocked) { throw new Error('blocked'); } storage.set(key, value); }
        },
        ajaxGet: (url, data, done) => reads.push({url, data, done}),
        ajaxCall: (url, data, done) => probes.push({url, data, done}),
        loadOverview: done => done(true), loadServiceState: done => done(true),
        trafficHistory: {add: () => {}}, lastMetadata: 0, fmtCount: String, updateTestAll() {}
    });
    // The production Poller defaults live in its module scope; inject fake timers
    // and visibility while retaining the actual non-overlapping poll behavior.
    context.MihomoUI = {...UI, Poller: class extends UI.Poller {
        constructor(request, interval) { super(request, interval, {
            hidden: () => pageDocument.hidden, schedule: () => 1, cancel: () => {}
        }); }
    }};
    const source = (proxyScript + '\nrenderGroups = () => {};\n' + lifecycleScript)
        .replace(/\{\{[\s\S]*?\}\}/g, match => JSON.stringify(match.match(/lang\._\('([^']*)'\)/)[1]));
    vm.runInContext(source, context);
    return {
        reads, probes, storage, element,
        refresh() { vm.runInContext('groupsPoller.refresh();', context); },
        reply(data, status = 'success') { assert(reads.length); reads.shift().done(data, status); },
        toggle(enabled) { const input = element('#auto-test-latency'); input.checked = enabled; input.handlers.change.call(input); },
        visibility(hidden) { pageDocument.hidden = hidden; events.visibilitychange(); },
        leave() { events.pagehide(); },
        manual(name) { element('#proxy-groups').handlers['click:.cmd-test'].call({attr: () => name}); }
    };
}
const autoGroups = [
    {name: 'outer', members: [
        {name: 'nested', type: 'Selector'}, {name: 'DIRECT', type: 'Direct'},
        {name: 'REJECT', type: 'Reject'}, {name: 'drop', type: 'RejectDrop'},
        {name: 'PASS', type: 'Pass'}, {name: 'unknown', type: ''},
        {name: 'dns', type: 'Dns'}, {name: 'empty group', type: 'URLTest'},
        {name: 'fallback', type: 'Fallback'}, {name: 'balance', type: 'LoadBalance'},
        {name: 'relay', type: 'Relay'}, {name: 'compat', type: 'Compatible'},
        {name: 'a&amp;&lt;b&gt;', type: 'Shadowsocks'}]},
    {name: 'nested', members: [{name: 'a&amp;&lt;b&gt;', type: 'Shadowsocks'},
        ...Array.from({length: 7}, (_, i) => ({name: 'node' + i, type: 'Vmess'}))]}
];
const readyGroups = {ready: true, groups: autoGroups};
assert.deepEqual(UI.automaticTestNames(autoGroups), ['a&<b>', ...Array.from({length: 7}, (_, i) => 'node' + i)]);
assert.deepEqual(UI.automaticTestNames([{name: 'g', members: []}]), []);
assert(!/checked/.test(indexView.match(/<input[^>]*id="auto-test-latency"[^>]*>/)[0]), 'HTML also defaults off');
for (const saved of [undefined, '0', 'true', 'garbage']) {
    const page = autoTestPage(saved);
    assert.equal(page.element('#auto-test-latency').checked, false);
    page.reply(readyGroups); page.refresh(); page.reply(readyGroups);
    assert.equal(page.probes.length, 0, 'No opt-in means no automatic probes');
    page.manual('node0');
    assert.equal(page.probes.length, 1, 'Manual tests still work with the experiment off');
}
const blockedPage = autoTestPage('1', true);
blockedPage.reply(readyGroups);
assert.equal(blockedPage.probes.length, 0, 'Storage failures default off');
blockedPage.toggle(true); blockedPage.reply(readyGroups);
assert.equal(blockedPage.probes.length, 3, 'Explicit opt-in still works without storage');

const autoPage = autoTestPage('1');
assert.equal(autoPage.element('#auto-test-latency').checked, true);
autoPage.reply(null, 'error');
autoPage.refresh(); autoPage.reply({ready: false, groups: autoGroups});
autoPage.refresh(); autoPage.reply({ready: true, groups: []});
assert.equal(autoPage.probes.length, 0, 'Failed, unreachable and empty reads do not consume the one run');
autoPage.refresh(); autoPage.reply(readyGroups);
assert.equal(autoPage.probes.length, 3);
autoPage.manual('extra'); autoPage.refresh();
assert.equal(autoPage.probes.length, 3, 'Manual actions and polls cannot overlap the sweep');
assert.equal(autoPage.reads.length, 0);
for (let i = 0; i < 8; i++) {
    assert.equal(autoPage.probes.length, Math.min(i + 3, 8), 'At most three requests are in flight');
    assert.equal(autoPage.probes[i].url, '/api/mihomo/dashboard/test_delay');
    autoPage.probes[i].done(i === 0 ? null : {status: 'ok'}, i === 0 ? 'error' : 'success');
}
assert.equal(new Set(autoPage.probes.map(probe => probe.data.name)).size, 8);
assert.match(autoPage.element('#proxy-test-state').label, /8\/8.*Failed: 1/);
autoPage.reply(readyGroups); autoPage.refresh(); autoPage.reply(readyGroups);
autoPage.toggle(false); autoPage.toggle(true);
assert.equal(autoPage.probes.length, 8, 'Completion refresh, polling and toggling cannot repeat the sweep');
assert.equal(autoPage.reads.length, 0);

for (const stop of ['disable', 'hide', 'leave']) {
    const page = autoTestPage();
    page.toggle(true); // While the initial read is still pending.
    assert.equal(page.storage.get('mihomo.autoTest.v1'), '1');
    page.reply(readyGroups);
    assert.equal(page.probes.length, 3);
    if (stop === 'disable') { page.toggle(false); assert.equal(page.storage.get('mihomo.autoTest.v1'), '0'); }
    if (stop === 'hide') { page.visibility(true); page.visibility(false); }
    if (stop === 'leave') { page.leave(); }
    page.probes.forEach(probe => probe.done({status: 'ok'}, 'success'));
    assert.equal(page.probes.length, 3, 'Stop discards queued probes: ' + stop);
    assert.match(page.element('#proxy-test-state').label, /3\/8.*Automatic tests stopped/);
    assert.equal(page.element('#proxy-groups .cmd-test, #proxy-groups .cmd-test-group').disabled, false);
    while (page.reads.length) { page.reply(readyGroups); }
    assert.equal(page.probes.length, 3);
}
const hiddenPage = autoTestPage('1');
hiddenPage.visibility(true); hiddenPage.reply(readyGroups);
assert.equal(hiddenPage.probes.length, 0, 'A response arriving in a hidden tab must not start probes');
hiddenPage.visibility(false); hiddenPage.reply(readyGroups);
assert.equal(hiddenPage.probes.length, 3, 'First visible successful read starts the sweep');
const disabledBeforeRead = autoTestPage('1');
disabledBeforeRead.toggle(false); disabledBeforeRead.reply(readyGroups);
assert.equal(disabledBeforeRead.probes.length, 0, 'Check the current opt-in when the read completes');
disabledBeforeRead.toggle(true); disabledBeforeRead.reply(readyGroups);
assert.equal(disabledBeforeRead.probes.length, 3, 'Disabling before any probes does not consume the one run');
const leftBeforeRead = autoTestPage('1');
leftBeforeRead.leave(); leftBeforeRead.reply(readyGroups);
assert.equal(leftBeforeRead.probes.length, 0, 'Late responses after navigation cannot start probes');
console.log('Experimental automatic latency: default-off, storage, opt-in, deduplication, bounded concurrency, one run, recovery and cancellation passed');

// Run the actual runtime-rules view: searching is over the complete snapshot,
// not the visible page. The DOM fixture rejects dynamic HTML parsing.
const rulesView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/runtime_rules.volt'), 'utf8');
assert(routingView.includes('href="#routing-rules"') && routingView.includes("partial('OPNsense/Mihomo/runtime_rules')"),
    'Policy Routing exposes the runtime-rule explorer');
const rulesScript = rulesView.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, text) => JSON.stringify(text));
const ruleControls = new Map(), ruleNodes = new Map(), ruleRequests = [];
const ruleDocument = {
    createElement(tag) { return new DomNode(this, tag); },
    getElementById(id) {
        if (!ruleNodes.has(id)) { ruleNodes.set(id, this.createElement(id === 'runtime-rule-type' ? 'select' : 'tbody')); }
        return ruleNodes.get(id);
    }
};
function ruleControl(selector) {
    if (!ruleControls.has(selector)) {
        ruleControls.set(selector, {value: '', label: '', handlers: {},
            val(value) { if (value === undefined) { return this.value; } this.value = value; return this; },
            text(value) { this.label = value; return this; },
            prop(key, value) { this[key] = value; return this; },
            on(event, fn) { this.handlers[event] = fn; return this; }
        });
    }
    return ruleControls.get(selector);
}
vm.runInNewContext(rulesScript, {
    document: ruleDocument, MihomoUI: UI,
    $: selector => selector === ruleDocument ? {ready: fn => fn()} : ruleControl(selector),
    ajaxGet: (url, params, done) => ruleRequests.push({url, params, done})
});
const ruleEvent = (id, event = 'click') => ruleControl('#runtime-rule-' + id).handlers[event]();
const ruleCells = () => ruleDocument.getElementById('runtime-rule-rows').children.map(row => row.children.map(cell => cell.textContent));
const ruleStatus = () => ruleControl('#runtime-rule-state').label;
const activateRules = () => ruleControl('a[href="#routing-rules"]').handlers['shown.bs.tab']();
assert.equal(ruleRequests.length, 0, 'Opening Policy Routing does not eagerly fetch all core rules');
activateRules(); activateRules(); ruleEvent('refresh');
assert.equal(ruleRequests.length, 1, 'Only one runtime rules request can be in flight');
assert.equal(ruleRequests[0].url, '/api/mihomo/dashboard/rules');
assert.equal(ruleControl('#runtime-rule-refresh').disabled, true);
ruleRequests[0].done(null, 'error');
assert.match(ruleStatus(), /unavailable/);
assert.equal(ruleControl('#runtime-rule-refresh').disabled, false);
activateRules();
const ruleFixture = Array.from({length: 112}, (_, i) => ({position: i + 1, type: 'DomainSuffix',
    payload: 'site-' + i + '.example.org', proxy: 'DIRECT'}));
ruleFixture[75] = {position: 76, type: 'RuleSet', payload: '中文-provider', proxy: 'Proxy &lt;&amp;&gt;'};
ruleFixture[111] = {position: 112, type: 'Match', payload: '', proxy: 'REJECT'};
ruleRequests[1].done({ready: true, rows: ruleFixture}, 'success');
assert.equal(ruleCells().length, 50);
assert.equal(ruleCells()[0][0], '1');
assert.equal(ruleControl('#runtime-rule-count').label, 'Showing 1–50 of 112 matches (112 loaded rules).');
assert.equal(ruleDocument.getElementById('runtime-rule-type').children.length, 4, 'Rule types are unique');
ruleEvent('next');
assert.equal(ruleCells()[0][0], '51');
assert.deepEqual(ruleCells()[25], ['76', 'RuleSet', '中文-provider', 'Proxy <&>'], 'Decode once and render proxy text safely');
ruleEvent('next');
assert.equal(ruleCells().length, 12);
assert.equal(ruleControl('#runtime-rule-next').disabled, true);
ruleEvent('prev');
assert.equal(ruleCells()[0][0], '51');
function searchRules(query) {
    ruleControl('#runtime-rule-search').val(query); ruleEvent('search', 'input');
}
searchRules('  PROXY <&>  ');
assert.deepEqual(ruleCells(), [['76', 'RuleSet', '中文-provider', 'Proxy <&>']], 'Search finds rows beyond the first page and matches decoded proxy targets');
searchRules('中文'); assert.equal(ruleCells()[0][0], '76');
searchRules('match'); assert.equal(ruleCells()[0][0], '112', 'Rule type is searchable');
searchRules('site-9'); assert.equal(ruleCells().length, 11, 'Payload search covers all pages');
ruleControl('#runtime-rule-type').val('Match'); ruleEvent('type', 'change');
assert.equal(ruleCells()[0][0], 'No matching rules.', 'Text and exact type filters combine');
assert.equal(ruleControl('#runtime-rule-count').label, 'Showing 0–0 of 0 matches (112 loaded rules).');
searchRules(''); assert.deepEqual(ruleCells(), [['112', 'Match', '', 'REJECT']]);
ruleEvent('clear');
assert.equal(ruleControl('#runtime-rule-type').value, '');
assert.equal(ruleCells()[0][0], '1');
searchRules('.*'); assert.equal(ruleCells()[0][0], 'No matching rules.', 'Search treats regular-expression metacharacters literally');
assert.equal(ruleRequests.length, 2, 'Filtering and paging issue no controller requests');
activateRules(); assert.equal(ruleRequests.length, 2, 'Tab switches retain the snapshot');
ruleEvent('clear'); ruleEvent('next'); ruleEvent('next'); ruleEvent('refresh');
ruleRequests[2].done({ready: false, rows: []}, 'success');
assert.match(ruleStatus(), /last successful snapshot/);
assert.equal(ruleCells()[0][0], '101', 'Failure retains the last successful page with a stale warning');
ruleEvent('refresh');
ruleRequests[3].done({ready: true, rows: ruleFixture.slice(0, 2)}, 'success');
assert.equal(ruleCells()[0][0], '1', 'Shrinking snapshots clamp the current page');
assert.match(ruleStatus(), /Snapshot loaded/);
ruleControl('#runtime-rule-type').val('DomainSuffix'); ruleEvent('type', 'change'); searchRules('site-1');
ruleEvent('refresh'); ruleRequests[4].done({ready: true, rows: ruleFixture}, 'success');
assert.equal(ruleControl('#runtime-rule-type').value, 'DomainSuffix');
assert.equal(ruleControl('#runtime-rule-search').value, 'site-1', 'Refresh preserves filters');
ruleEvent('refresh'); ruleRequests[5].done({ready: true, rows: []}, 'success');
assert.equal(ruleControl('#runtime-rule-type').value, '', 'Removed types fall back to all types');
assert.equal(ruleControl('#runtime-rule-count').label, 'Showing 0–0 of 0 matches (0 loaded rules).');
assert.equal(ruleControl('#runtime-rule-prev').disabled, true);
assert.equal(ruleControl('#runtime-rule-next').disabled, true);
console.log('Runtime rule search, type filters, full-snapshot paging, safe text, lazy refresh and failures: all checks passed');
const formatUptime = require('../src/usr/local/www/js/mihomo/ui.js').formatUptime;
for (const [seconds, expected] of [[0, '00:00:00'], [59, '00:00:59'], [60, '00:01:00'],
    [3599, '00:59:59'], [3600, '01:00:00'], [90061, '25:01:01'], [360000, '100:00:00']]) {
    assert.equal(formatUptime(seconds), expected);
}
for (const value of [null, undefined, '', '60', -1, 1.5, NaN, Infinity]) {
    assert.equal(formatUptime(value), null, 'Unknown uptime must not look like a newly started core');
}
const timingLabels = new Map(), timingHandlers = {}, timingDocument = {};
const timingScript = indexView.slice(indexView.indexOf('        let processMemory = null;'),
    indexView.indexOf('        let storedHistory = []'))
    .replace(/\{\{[\s\S]*?\}\}/g, '"Unavailable"');
const timingContext = {
    document: timingDocument, Date, MihomoUI: {formatUptime}, fmtBytes: String,
    $: selector => selector === timingDocument
        ? {on: (event, handler) => { timingHandlers[event] = handler; }}
        : {text: value => timingLabels.set(selector, value)}
};
vm.runInNewContext(timingScript, timingContext);
const runtimeTiming = (seconds, lastReload = 1700000000) => timingHandlers['mihomo:runtime'](null,
    {process: {rss: 1024, uptime_seconds: seconds}, last_reload_at: lastReload});
runtimeTiming(90061);
assert.equal(timingLabels.get('#stat-uptime'), '25:01:01');
assert.equal(timingLabels.get('#stat-last-reload'), new Date(1700000000000).toLocaleString());
runtimeTiming(0, 1700000060);
assert.equal(timingLabels.get('#stat-uptime'), '00:00:00', 'Restart resets age without retaining the old uptime');
assert.equal(timingLabels.get('#stat-last-reload'), new Date(1700000060000).toLocaleString());
timingHandlers['mihomo:runtime'](null, {process: null, last_reload_at: 1700000060});
assert.equal(timingLabels.get('#stat-uptime'), 'Unavailable', 'Stopped core has no age');
assert.equal(timingLabels.get('#stat-last-reload'), new Date(1700000060000).toLocaleString(), 'Stopping retains last success');
for (const value of [null, undefined, 0, -1, '1700000000', '<img src=x>', Number.MAX_SAFE_INTEGER]) {
    timingHandlers['mihomo:runtime'](null, {process: null, last_reload_at: value});
    assert.equal(timingLabels.get('#stat-uptime'), 'Unavailable');
    assert.equal(timingLabels.get('#stat-last-reload'), 'Unavailable');
}
// Drive the shared runtime poll's real failure path and its overview event handler.
const networkView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/network_status.volt'), 'utf8');
const runtimeRefresh = networkView.match(/    function refresh\(done\) \{[\s\S]*?\n    \}/)[0]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
for (const [data, status] of [[null, 'error'], [{status: 'unavailable'}, 'success']]) {
    runtimeTiming(90);
    vm.runInNewContext('let lastDns = 0, dnsPending = false;\n' + runtimeRefresh + '\nrefresh(done);', {
        Date: {now: () => 0}, document: timingDocument,
        $root: {find: () => ({prop: () => {}, text: () => {}})},
        $: () => ({trigger: event => timingHandlers[event]()}),
        ajaxGet: (url, params, done) => done(data, status), done: ok => assert.equal(!!ok, false)
    });
    assert.equal(timingLabels.get('#stat-uptime'), 'Unavailable', 'Failed polls must clear old age');
    assert.equal(timingLabels.get('#stat-last-reload'), 'Unavailable');
}
runtimeTiming(120);
assert.equal(timingLabels.get('#stat-uptime'), '00:02:00', 'Polling recovery restores timing');
assert(indexView.includes('id="stat-uptime"') && indexView.includes('id="stat-last-reload"'));
console.log('Core uptime, reload timestamps, stopped cores, failed polls and recovery: all checks passed');
// Execute the real overview renderer and request callback for rule-count lifecycle.
const ruleLabels = new Map();
const ruleCountRequests = [];
const ruleContext = {
    renderClients() {}, renderTrafficTotals() {}, trafficTotals: new UI.TrafficTotals(), latestTotals: null,
    Date: {now: () => now}, processMemory: null, lastHistorySave: now, lastMetadata: 0,
    fmtCount: value => Number(value).toLocaleString('en-US'), fmtBytes: String,
    trafficHistory: {add: () => ({down: null, up: null})}, drawTraffic: () => {},
    ajaxGet: (url, data, done) => ruleCountRequests.push({data, done}),
    $: selector => ({
        text: value => ruleLabels.set(selector, value), data: () => false, val: () => {}
    })
};
const overviewRenderer = indexView.match(/        function renderOverview\(data\) \{[\s\S]*?\n        \}/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
vm.runInNewContext('function renderModeHint() {}\n' + overviewRenderer + '\n' + overviewFunction, ruleContext);
const renderRuleCount = (runtime, alive = true) => {
    ruleContext.data = {runtime: {ready: true, ...runtime}, controller: {alive}};
    vm.runInNewContext('renderOverview(data);', ruleContext);
    return ruleLabels.get('#stat-rules');
};
assert(indexView.includes('id="stat-rules"'), 'Overview has a visible rule count');
assert.equal(renderRuleCount({ruleCount: 1234}), '1,234');
assert.equal(renderRuleCount({}), '1,234', 'Fast polls retain the metadata count');
assert.equal(renderRuleCount({ruleCount: 0}), '0', 'An empty rules list is a valid zero');
for (const ruleCount of [null, -1, 1.5, '12', {}, NaN]) {
    assert.equal(renderRuleCount({ruleCount}), 'Unavailable', 'Unknown or malformed counts must not appear as zero');
}
assert.equal(renderRuleCount({ruleCount: 2}), '2', 'A config reload updates the count');
assert.equal(renderRuleCount({ready: false}), 'Unavailable', 'Lost runtime clears the cached count');
assert.equal(renderRuleCount({ruleCount: 2}, false), 'Unavailable', 'Stopped controller clears the count');
assert.equal(renderRuleCount({ruleCount: 4}), '4', 'Controller recovery restores the count');
vm.runInNewContext('loadOverview();', ruleContext);
ruleCountRequests.at(-1).done(null, 'error');
assert.equal(ruleLabels.get('#stat-rules'), 'Unavailable', 'Transport failure clears the cached count');
now += 2000;
vm.runInNewContext('loadOverview();', ruleContext);
assert.equal(ruleCountRequests.at(-1).data.metadata, 1, 'Recovery requests fresh metadata');
ruleCountRequests.at(-1).done({runtime: {ready: true, ruleCount: 7}, controller: {alive: true}}, 'success');
assert.equal(ruleLabels.get('#stat-rules'), '7');
now += 2000;
vm.runInNewContext('loadOverview();', ruleContext);
assert.equal(ruleCountRequests.at(-1).data.metadata, 0);
ruleCountRequests.at(-1).done({runtime: {ready: true}, controller: {alive: true}}, 'success');
assert.equal(ruleLabels.get('#stat-rules'), '7');
console.log('Overview rule counts: formatting, zero, unavailable, reload, fast polling and recovery passed');
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
    renderClients: () => {}, // Client rendering is exercised separately below.
    overviewPoller: {refresh: () => { modeRefreshes++; }},
    ajaxCall: (url, data, done) => modeWrites.push({url, data, done}),
    setTimeout: fn => modeTimeouts.push(fn), actionFailed: () => { modeFailures++; },
    renderTrafficTotals() {}, trafficTotals: new UI.TrafficTotals()
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
const renderGroupsScript = indexView.match(/        let renderedGroups = null;[\s\S]*?(?=        let exportingSelections = false;)/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
let groupAllocations = 0;
const pollingDoc = {activeElement: null, createElement(tag) { groupAllocations++; return new DomNode(this, tag); }, createElementNS: doc.createElementNS};
const pollingBox = pollingDoc.createElement('div');
let noteHandler;
let favoriteNotice = '', testsDisabled = false, favoriteHandler, nodeOrderHandler, collapseHandler, testGroupHandler;
let selectionDisabled = false, selectionRefreshes = 0, selectionFailures = 0, clearedActions = 0;
const selectionHandlers = {}, selectionRequests = [];
let testAllDisabled = true, testAllHandler, testProgress = '';
const noteControls = new Map();
function noteControl(selector) {
    if (!noteControls.has(selector)) {
        const node = pollingDoc.createElement('input');
        node.focus = () => { pollingDoc.activeElement = node; };
        noteControls.set(selector, {0: node, value: '', label: '', hidden: true, handlers: {},
            text(value) { this.label = value; return this; },
            val(value) { if (value === undefined) { return this.value; } this.value = value; return this; },
            prop(key, value) { this[key] = value; return this; },
            on(event, handler) { this.handlers[event] = handler; return this; }});
    }
    return noteControls.get(selector);
}
const dashboardStorage = new Map();
const dashboardFavorites = new UI.ProxyFavorites(() => ({
    getItem: key => dashboardStorage.get(key) || null,
    setItem: (key, value) => dashboardStorage.set(key, value)
}));
const proxyFilterControl = {
    value: '', focused: false, handlers: {},
    on(event, handler) { this.handlers[event] = handler; return this; },
    val(value) { this.value = value; return this; },
    trigger(event) {
        if (event === 'focus') { this.focused = true; }
        else { this.handlers[event].call(this); }
        return this;
    }
};
let proxyFilterStatus = '', proxyFilterClear;
const groupContext = vm.createContext({
    $: selector => {
        if (selector === '#proxy-filter') { return proxyFilterControl; }
        if (selector === '#proxy-filter-clear') { return {on: (event, handler) => { assert.equal(event, 'click'); proxyFilterClear = handler; }}; }
        if (selector === '#proxy-filter-state') {
            return {text: value => { proxyFilterStatus = value; }, empty: () => { proxyFilterStatus = ''; }};
        }
        if (selector === '#proxy-node-order') {
            return {on: (event, handler) => { assert.equal(event, 'change'); nodeOrderHandler = handler; }};
        }
        if (selector instanceof DomNode) {
            return {attr: key => selector.getAttribute(key), closest: target => {
                if (target === 'li') {
                    const member = pollingBox.querySelectorAll('li[data-member]').find(node => node.contains(selector));
                    return {attr: key => member.getAttribute(key)};
                }
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
        if (selector === '#dashboard-action-state') { return {empty: () => { clearedActions++; }}; }
        if (selector === '#proxy-groups .cmd-select, #proxy-groups .cmd-reset-group') {
            return {prop: (key, value) => { assert.equal(key, 'disabled'); selectionDisabled = value; }};
        }
        if (selector === '#test-all-groups') {
            return {prop: (key, value) => { assert.equal(key, 'disabled'); testAllDisabled = value; },
                on: (event, handler) => { assert.equal(event, 'click'); testAllHandler = handler; }};
        }
        if (selector === '#proxy-test-state') { return {text: value => { testProgress = value; }}; }
        if (selector === '#proxy-groups .cmd-test') {
            return {each: fn => pollingBox.querySelectorAll('button[data-name]')
                .filter(node => node.attrs.class.includes(' cmd-test')).forEach(node => fn.call(node))};
        }
        if (selector.startsWith('#proxy-note-')) { return noteControl(selector); }
        if (selector === '#proxy-autoswitch-state') { return {empty() {}}; }
        if (selector === '#stop-proxy-tests') { return {prop() {}}; }
        if (selector === '#proxy-health-summary') { return {text() {}}; }
        if (selector === '#proxy-groups .cmd-test, #proxy-groups .cmd-test-group') {
            return {prop: (key, value) => { assert.equal(key, 'disabled'); testsDisabled = value; }};
        }
        assert.equal(selector, '#proxy-groups');
        return {0: pollingBox, on: (event, target, handler) => {
            assert.equal(event, 'click');
            if (target === '.cmd-favorite') { favoriteHandler = handler; }
            else if (target === '.cmd-collapse-group') { collapseHandler = handler; }
            else if (target === '.cmd-test-group') { testGroupHandler = handler; }
            else if (target === '.cmd-proxy-note') { noteHandler = handler; }
            else { selectionHandlers[target] = handler; }
        }, html: text => {
            const placeholder = pollingDoc.createElement('placeholder');
            placeholder.textContent = text;
            pollingBox.replaceChildren(placeholder);
        }};
    },
    MihomoUI: UI, favorites: dashboardFavorites, latestGroups: null, testing: false, selecting: false,
    nodeOrder: 'config', snapshotBusy: false, groupsRevision: 0, cancelAutoSwitch() {},
    ajaxCall: (url, params, done) => { selectionRequests.push({url, params, done}); },
    groupsPoller: {refresh: () => { selectionRefreshes++; }},
    actionFailed: () => { selectionFailures++; },
    localStorage: {getItem: key => dashboardStorage.get(key) || null, setItem: (key, value) => dashboardStorage.set(key, value)},
    delayText: value => value + ' ms', delayClass: () => 'label-success'
});
const collapseStateScript = indexView.match(/        const collapsedGroups = new Set\(\);[^\n]*/)[0];
const noteStateScript = indexView.match(/        const proxyNotes = new MihomoUI.ProxyNotes\(\);/)[0];
// Inject storage explicitly because UI constructors run in Node's context.
groupContext.MihomoUI = {...UI, ProxyNotes: class extends UI.ProxyNotes {
    constructor() { super(() => groupContext.localStorage); }
}};
vm.runInContext(collapseStateScript + '\n' + noteStateScript + '\n' + renderGroupsScript, groupContext);
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
    () => { groupResponse.groups[0].members[0].delay_history = [10, 20]; },
    () => { groupResponse.groups[0].members[0].delay_history = [30, 20]; },
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

// Bulk selection reports preserve exact names and only export allowlisted fields.
const selectionGroups = [
    {name: '手动 &amp; &lt;组&gt;', type: 'Selector', now: '节点 "A"\\line\nnext',
        members: [{name: 'old', selected: true}], secret: 'excluded-test-value'},
    {name: '__proto__', type: 'URLTest', now: 'literal &amp;gt;'},
    {name: '001', type: 'Fallback', now: 'DIRECT'},
    {name: 'balanced', type: 'LoadBalance', now: ''},
    {name: 'unknown', type: 'Selector'},
    {name: 'nested', type: 'Selector', now: '手动 &amp; &lt;组&gt;'}
];
const capturedAt = '2026-11-15T12:00:00.000Z';
const originalSelectionGroups = JSON.stringify(selectionGroups);
const selectionText = UI.exportSelections(selectionGroups, capturedAt);
assert.deepEqual(JSON.parse(selectionText), {capturedAt, groups: [
    {group: '手动 & <组>', type: 'Selector', selected: '节点 "A"\\line\nnext'},
    {group: '__proto__', type: 'URLTest', selected: 'literal &gt;'},
    {group: '001', type: 'Fallback', selected: 'DIRECT'},
    {group: 'balanced', type: 'LoadBalance', selected: null},
    {group: 'unknown', type: 'Selector', selected: null},
    {group: 'nested', type: 'Selector', selected: '手动 & <组>'}
]});
assert.equal(JSON.stringify(selectionGroups), originalSelectionGroups, 'Export must not mutate selections');
assert(!selectionText.includes('excluded-test-value'));
assert(!selectionText.includes('members'));
assert.deepEqual(JSON.parse(UI.exportSelections([], capturedAt)), {capturedAt, groups: []});

// Run the actual export controls. No clipboard permission, write API, or storage
// is available: the read-only textarea must be sufficient to copy the report.
const exportScript = indexView.match(/        let exportingSelections = false;[\s\S]*?(?=        let copying = false;)/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
const selectionExportControlsFixture2 = new Map(), exportRequestsFixture3 = [];
function selectionExportControl(selector) {
    if (!selectionExportControlsFixture2.has(selector)) {
        const item = {value: '', label: '', handlers: {}, hidden: true, disabled: false, focused: false, selected: false,
            prop(key, value) { this[key] = value; return this; },
            val(value) { this.value = value; return this; },
            text(value) { this.label = value; return this; },
            empty() { this.label = ''; return this; },
            on(event, handler) { this.handlers[event] = handler; return this; },
            focus() { this.focused = true; }, select() { this.selected = true; }};
        item[0] = item;
        selectionExportControlsFixture2.set(selector, item);
    }
    return selectionExportControlsFixture2.get(selector);
}
vm.runInNewContext(exportScript, {
    $: selectionExportControl, MihomoUI: UI,
    ajaxGet: (url, params, done) => exportRequestsFixture3.push({url, params, done})
});
const exportButtonFixture4 = selectionExportControl('#export-selections');
const exportField = selectionExportControl('#selection-export-text');
const exportPanel = selectionExportControl('#selection-export-panel');
const exportState = selectionExportControl('#selection-export-state');
const exportClick = () => exportButtonFixture4.handlers.click();
assert.equal(exportRequestsFixture3.length, 0, 'Export is strictly on demand');
exportClick(); exportClick();
assert.equal(exportRequestsFixture3.length, 1, 'Repeated clicks must not overlap requests');
assert.equal(exportRequestsFixture3[0].url, '/api/mihomo/dashboard/proxies');
assert.equal(Object.keys(exportRequestsFixture3[0].params).length, 0);
assert.equal(exportButtonFixture4.disabled, true);
exportRequestsFixture3[0].done({ready: true, groups: selectionGroups}, 'success');
assert.equal(exportButtonFixture4.disabled, false);
assert.equal(exportPanel.hidden, false);
assert(exportField.focused && exportField.selected, 'The snippet is ready for manual copy');
const exportedReport = JSON.parse(exportField.value);
assert.deepEqual(exportedReport.groups, JSON.parse(selectionText).groups);
assert(!Number.isNaN(Date.parse(exportedReport.capturedAt)));
assert(exportState.label.includes('Ctrl+C'));
selectionGroups[0].now = 'changed since export';
assert.equal(exportField.value.includes('changed since export'), false, 'A report stays fixed while copying');
exportClick();
assert.equal(exportField.value, '', 'A new read clears the previous report');
assert.equal(exportPanel.hidden, true);
exportRequestsFixture3.at(-1).done({ready: true, groups: selectionGroups}, 'success');
assert.equal(JSON.parse(exportField.value).groups[0].selected, 'changed since export', 'Each export reads fresh selections');
selectionExportControl('#selection-export-dismiss').handlers.click();
assert.equal(exportPanel.hidden, true);
assert.equal(exportField.value, '');
assert.equal(exportState.label, '');
assert.equal(exportButtonFixture4.focused, true);
for (const [data, status] of [
    [null, 'error'], [{ready: false, groups: selectionGroups}, 'success'],
    [{ready: true, groups: selectionGroups}, 'error'], [{ready: true}, 'success']
]) {
    exportClick();
    exportRequestsFixture3.at(-1).done(data, status);
    assert.equal(exportButtonFixture4.disabled, false, 'A failed read permits retry');
    assert.equal(exportPanel.hidden, true);
    assert.equal(exportField.value, '', 'Never offer stale data after a failed export');
    assert.equal(exportState.label, 'Could not read current selections. Try exporting again.');
}
exportClick();
exportRequestsFixture3.at(-1).done({ready: true, groups: []}, 'success');
assert.equal(exportState.label, 'No proxy groups are defined in the configuration.');
assert.equal(exportPanel.hidden, true);
assert.match(indexView, /<textarea[^>]*id="selection-export-text"[^>]* readonly[^>]*aria-describedby="selection-export-help"/);
console.log('Selection export: exact names, all group types, safe fields, fresh reads, manual copy, retry and empty results passed');
// Named snapshots retain only exact Selector selections, across page instances.
function memoryStorage() {
    const values = new Map();
    return {getItem: key => values.has(key) ? values.get(key) : null, setItem: (key, value) => values.set(key, value)};
}
const snapshotStorage = memoryStorage();
const snapshots = new UI.ProxySnapshots(snapshotStorage);
const snapshotName = '<Work> & "中文"';
const snapshotGroups = [
    {name: encode('__proto__'), type: 'Selector', now: encode('literal &gt; <node>'), members: [{name: encode('literal &gt; <node>')}, {name: 'other'}], secret: 'never-store-this'},
    {name: encode('中文 / "group"'), type: 'Selector', now: 'DIRECT', members: [{name: 'DIRECT'}, {name: 'other'}]},
    {name: 'Auto', type: 'URLTest', now: 'fast', members: [{name: 'fast'}]},
    {name: 'Fallback', type: 'Fallback', now: 'fast', members: [{name: 'fast'}]}
];
assert.equal(snapshots.save(' ' + snapshotName + ' ', snapshotGroups), snapshotName);
const savedSnapshot = new UI.ProxySnapshots(snapshotStorage).read()[0];
assert.deepEqual(savedSnapshot, {name: snapshotName, selections: [
    {group: '__proto__', member: 'literal &gt; <node>'}, {group: '中文 / "group"', member: 'DIRECT'}
]});
assert(!snapshotStorage.getItem(snapshots.key).includes('never-store-this'));
assert(!snapshotStorage.getItem(snapshots.key).includes('URLTest'));
assert.throws(() => snapshots.save(snapshotName, snapshotGroups), /duplicate/);
assert.throws(() => snapshots.save(' ', snapshotGroups), /name/);
assert.throws(() => snapshots.save('x'.repeat(81), snapshotGroups), /name/);
assert.throws(() => snapshots.save('auto only', snapshotGroups.slice(2)), /empty/);
assert.throws(() => snapshots.save('bad current', [{...snapshotGroups[0], now: 'gone'}]), /groups/);
assert.throws(() => snapshots.save('malformed', [{}]), /groups/);
assert.throws(() => snapshots.save('ambiguous', [snapshotGroups[0], snapshotGroups[0]]), /groups/);
assert.deepEqual(UI.planProxySnapshot(savedSnapshot, snapshotGroups), {changes: [], missing: []});
const changedGroups = snapshotGroups.map(group => ({...group, now: 'other'}));
assert.deepEqual(UI.planProxySnapshot(savedSnapshot, changedGroups).changes, [
    {group: '__proto__', member: 'literal &gt; <node>', previous: 'other'},
    {group: '中文 / "group"', member: 'DIRECT', previous: 'other'}
]);
for (const groups of [changedGroups.slice(1), [{...changedGroups[0], type: 'URLTest'}, ...changedGroups.slice(1)],
    [{...changedGroups[0], members: [{name: 'other'}]}, ...changedGroups.slice(1)]]) {
    assert.deepEqual(UI.planProxySnapshot(savedSnapshot, groups).missing, ['__proto__']);
}
for (let i = 1; i < 20; i++) { snapshots.save(String(i), snapshotGroups); }
assert.throws(() => snapshots.save('overflow', snapshotGroups), /limit/);
snapshots.remove('1'); snapshots.save('replacement', snapshotGroups);
assert.equal(snapshots.read().length, 20);
const beforeStorageFailure = snapshots.read();
const originalSet = snapshotStorage.setItem;
snapshotStorage.setItem = () => { throw new Error('quota'); };
assert.throws(() => snapshots.remove(snapshotName), /quota/);
assert.deepEqual(snapshots.read(), beforeStorageFailure, 'Failed storage writes retain saved snapshots');
snapshotStorage.setItem = originalSet;
for (const invalid of ['{', 'null', '[]', '{"version":2,"snapshots":[]}',
    JSON.stringify({version: 1, snapshots: [{name: 'bad', selections: []}]}),
    JSON.stringify({version: 1, snapshots: [savedSnapshot, savedSnapshot]})]) {
    const broken = memoryStorage(); broken.setItem(snapshots.key, invalid);
    assert.throws(() => new UI.ProxySnapshots(broken).read());
}
console.log('Proxy snapshots: persistence, exact names, selectors, validation, limits and storage failures passed');

// Execute actual overview controls, requests, locks and restore sequencing.
const snapshotScript = indexView.slice(indexView.indexOf('        let testing = false;'), indexView.indexOf('        /*', indexView.indexOf('        function loadGroups(done)')))
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
assert(snapshotScript.includes('proxy-snapshot-restore'), 'The overview must wire snapshot controls');
function snapshotPage(storage = memoryStorage()) {
    const items = new Map(), gets = [], posts = [], confirms = [];
    const document = {hidden: false, addEventListener() {}, createElement: tag => new DomNode(document, tag), getElementById: id => item('#' + id)[0]};
    function item(selector) {
        if (typeof selector !== 'string') { return selector; }
        if (!items.has(selector)) {
            items.set(selector, {0: document.createElement('select'), value: '', label: '', handlers: {}, disabled: false,
                val(value) { if (value === undefined) { return this.value; } this.value = value; return this; },
                text(value) { if (value === undefined) { return this.label; } this.label = value; return this; }, empty() { this.label = ''; return this; },
                prop(key, value) { this[key] = value; return this; },
                on(event, selector, fn) { this.handlers[fn ? selector : event] = fn || selector; return this; }});
        }
        return items.get(selector);
    }
    const page = {item, gets, posts, confirms, refreshes: 0, renders: 0, confirm: true};
    const context = vm.createContext({document, $: item, MihomoUI: UI, fmtCount: String, updateTestAll() {},
        window: {addEventListener() {}, get localStorage() { if (!storage) { throw new Error('denied'); } return storage; },
            confirm: text => { confirms.push(text); return page.confirm; }},
        ajaxGet: (url, data, done) => gets.push({url, data, done}),
        ajaxCall: (url, data, done) => posts.push({url, data, done}),
        groupsPoller: {refresh: () => { page.refreshes++; }}, renderGroups: () => { page.renders++; }, actionFailed: () => {}
    });
    vm.runInContext(snapshotScript, context);
    page.click = action => item('#proxy-snapshot-' + action).handlers.click();
    page.read = groups => gets.at(-1).done({ready: true, groups}, 'success');
    page.poll = () => vm.runInContext('loadGroups(() => {});', context);
    page.state = () => item('#proxy-snapshot-state').label;
    page.store = new UI.ProxySnapshots(storage);
    page.context = context;
    return page;
}
const page = snapshotPage();
assert.equal(page.gets.length + page.posts.length, 0, 'Loading never saves or restores automatically');
page.item('#proxy-snapshot-name').val(snapshotName);
page.click('save'); page.click('save');
assert.equal(page.gets.length, 1, 'Save fetches once and rejects overlapping actions');
page.read(snapshotGroups);
assert.equal(page.store.read()[0].name, snapshotName);
assert.equal(page.item('#proxy-snapshot-list')[0].children[1].textContent, snapshotName, 'Snapshot labels are literal text');
assert.equal(page.posts.length, 0);
page.poll(); const stalePoll = page.gets.at(-1);
page.click('restore');
stalePoll.done({ready: true, groups: snapshotGroups}, 'success');
assert.equal(page.renders, 0, 'Old polls cannot render across snapshot operations');
page.read(changedGroups);
assert.equal(page.confirms.length, 1);
assert(page.confirms[0].includes('literal &gt; <node>'));
assert.equal(page.posts.length, 1, 'Restore issues one selection at a time');
assert.equal(page.posts[0].url, '/api/mihomo/dashboard/select_proxy');
assert.deepEqual({...page.posts[0].data}, {group: '__proto__', member: 'literal &gt; <node>'});
const readsWhileBusy = page.gets.length;
page.click('save'); page.click('delete'); page.click('restore'); page.poll();
page.item('#proxy-groups').handlers['.cmd-select'].call({closest: () => ({attr: () => ''})});
assert.equal(page.gets.length, readsWhileBusy);
assert.equal(page.posts.length, 1, 'Manual selections cannot interleave with restore');
page.posts[0].done({status: 'ok'}, 'success');
assert.equal(page.posts.length, 2);
page.posts[1].done(null, 'error');
assert(page.state().includes('1/2'));
assert(page.state().includes('unconfirmed'));
assert.equal(page.store.read().length, 1, 'Partial restore does not mutate the snapshot');
assert(page.refreshes >= 2, 'Completion refreshes current selections');
page.click('restore'); page.read(changedGroups);
page.posts[2].done({status: 'failed'}, 'success');
assert.equal(page.posts.length, 3, 'A rejected write stops the remaining queue');
assert(page.state().includes('0/2'));
page.click('restore'); page.read([{...changedGroups[0], now: snapshotGroups[0].now}, ...changedGroups.slice(1)]);
assert.equal(page.posts.length, 4, 'Already active selections are skipped on retry');
page.posts[3].done({status: 'ok'}, 'success');
assert(page.state().includes('1/1'));
for (const groups of [changedGroups.slice(1), [{...changedGroups[0], type: 'Fallback'}, ...changedGroups.slice(1)],
    [{...changedGroups[0], members: []}, ...changedGroups.slice(1)]]) {
    page.click('restore'); page.read(groups);
    assert(page.state().includes('Restore blocked'));
    assert.equal(page.posts.length, 4, 'Any incompatible saved selection blocks all writes');
}
page.click('restore'); page.read(snapshotGroups);
assert(page.state().includes('already active'));
page.confirm = false; page.click('restore'); page.read(changedGroups);
assert(page.state().includes('cancelled'));
assert.equal(page.posts.length, 4);
for (const action of ['save', 'restore']) {
    page.click(action); page.gets.at(-1).done({ready: false}, 'success');
    assert(page.state().includes('No changes'));
    page.click(action); page.gets.at(-1).done(null, 'error');
    assert(page.state().includes('No changes'));
}
const manualButton = {prop() {}, closest: () => ({attr: name => name === 'data-group' ? '__proto__' : 'other'})};
page.item('#proxy-groups').handlers['.cmd-select'].call(manualButton);
const readsBeforeSelection = page.gets.length;
page.click('save'); page.click('restore');
assert.equal(page.gets.length, readsBeforeSelection, 'Snapshots wait for pending manual selections');
page.posts.at(-1).done({status: 'ok'}, 'success');
page.click('delete');
assert.equal(page.store.read().length, 0);
const deniedPage = snapshotPage(null);
assert(deniedPage.state().includes('storage'));
deniedPage.item('#proxy-snapshot-name').val('Denied'); deniedPage.click('save'); deniedPage.read(snapshotGroups);
assert(deniedPage.state().includes('storage'));
assert.equal(deniedPage.posts.length, 0);
const fullStorage = memoryStorage();
fullStorage.setItem = () => { throw new Error('quota'); };
const quotaPage = snapshotPage(fullStorage);
quotaPage.item('#proxy-snapshot-name').val('Full'); quotaPage.click('save'); quotaPage.read(snapshotGroups);
assert(quotaPage.state().includes('storage'));
assert.equal(quotaPage.store.read().length, 0);
console.log('Proxy snapshot controls: fresh reads, preview/cancel, sequential writes, partial failure, compatibility and request races passed');
// Client traffic uses the overview snapshot, never the paged connection grid.
// Run the real load/render path to cover failures, unchanged polls and recovery.
const clientScript = indexView.match(/        let renderedClients;[\s\S]*?(?=        \/\* -)/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
const clientBox = doc.createElement('div'), clientRequests = [], clientPollResults = [];
const clientContext = vm.createContext({
    trafficTotals: new UI.TrafficTotals(), latestTotals: null, renderTrafficTotals() {},
    document: {getElementById: id => { assert.equal(id, 'client-traffic'); return clientBox; }},
    $: () => ({text() {}, val() {}, data() { return false; }}),
    MihomoUI: UI, lastMetadata: 0, lastHistorySave: 0, processMemory: null,
    fmtCount: String, fmtBytes: UI.formatBytes, fmtRate: String,
    trafficHistory: {add: () => ({down: null, up: null}), samples: []},
    drawTraffic() {}, renderModeHint() {}, // Mode hints are exercised separately above.
    sessionStorage: {setItem() {}},
    ajaxGet: (url, params, done) => clientRequests.push({url, params, done}),
    done: ok => clientPollResults.push(ok)
});
vm.runInContext(clientScript, clientContext);
function pollClients(data, status = 'success') {
    vm.runInContext('loadOverview(done);', clientContext);
    assert.equal(clientRequests.at(-1).url, '/api/mihomo/dashboard/overview');
    clientRequests.at(-1).done(data, status);
}
const clientResponse = {controller: {alive: true}, runtime: {ready: true, clients: {total: 14, rows: [
    {source: '2001:db8::1', connections: 2, download: 1536, upload: 1024},
    {source: '', connections: 1, download: 0, upload: 0},
    {source: '&lt;img src=x onerror=alert(1)&gt;&amp;amp;', connections: 1, download: 0, upload: 0}
]}}};
const clientRows = () => clientBox.children[0].children[2].children.map(row => row.children.map(cell => cell.textContent));
pollClients(clientResponse);
assert.equal(clientBox.children[0].tagName, 'table');
assert.equal(clientBox.children[0].children[0].textContent, 'Clients shown: 3 / 14');
assert.deepEqual(clientRows(), [
    ['2001:db8::1', '2', UI.formatBytes(1536), UI.formatBytes(1024)],
    ['Unknown source', '1', UI.formatBytes(0), UI.formatBytes(0)],
    ['<img src=x onerror=alert(1)>&amp;', '1', UI.formatBytes(0), UI.formatBytes(0)]
]);
assert.equal(clientBox.children[0].children[1].children[0].children[0].attrs.scope, 'col');
assert.equal(clientBox.children[0].children[2].children[0].children[0].attrs.scope, 'row');
const retainedClientTable = clientBox.children[0];
pollClients(JSON.parse(JSON.stringify(clientResponse)));
assert.equal(clientBox.children[0], retainedClientTable, 'Identical client summaries retain table nodes');
clientResponse.runtime.clients.rows[0].download = 2048;
pollClients(clientResponse);
assert.notEqual(clientBox.children[0], retainedClientTable);
assert.equal(clientRows()[0][2], UI.formatBytes(2048));
for (const unavailable of [null, {runtime: {ready: false}}, {runtime: {ready: true}, controller: {alive: false}}]) {
    pollClients(unavailable);
    assert.equal(clientBox.children[0].tagName, 'p');
    assert.equal(clientBox.children[0].textContent, 'Client traffic is unavailable.', 'Failures cannot leave unmarked stale client totals');
    pollClients(clientResponse);
    assert.equal(clientBox.children[0].tagName, 'table', 'The same snapshot reappears after recovery');
}
pollClients(clientResponse, 'error');
assert.equal(clientBox.children[0].textContent, 'Client traffic is unavailable.');
assert.equal(clientPollResults.at(-1), false);
pollClients({controller: {alive: true}, runtime: {ready: true, clients: {rows: [], total: 0}}});
assert.equal(clientBox.children[0].textContent, 'No active connections.');
assert.equal(clientPollResults.at(-1), true);
pollClients(clientResponse);
assert.equal(clientBox.children[0].tagName, 'table');
console.log('Client traffic rendering, active-only totals, unavailable/empty states and overview polling: all checks passed');
const failedResponse = {ready: true, groups: [{name: encode('<Failed>&'), members: [candidate('node')]}]};
pollGroups(failedResponse);
assert.equal(warningBadges(pollingBox)[0].textContent, 'No usable proxies');
const warnedRow = pollingBox.children[0];
pollGroups(failedResponse);
assert.equal(pollingBox.children[0], warnedRow, 'Unchanged warnings do not redraw');
failedResponse.groups[0].members[0].delay = 12;
pollGroups(failedResponse);
assert.equal(warningBadges(pollingBox).length, 0, 'Successful latest test removes the warning');
failedResponse.groups[0].members[0].delay = 0;
pollGroups(failedResponse);
assert.equal(warningBadges(pollingBox).length, 1);
pollGroups({ready: false});
assert.equal(warningBadges(pollingBox).length, 0, 'Unavailable controller must not be reported as an empty group');
pollGroups(failedResponse);
assert.equal(warningBadges(pollingBox).length, 1, 'Recovery restores the current warning');
pollGroups({ready: true, groups: []});
assert.equal(warningBadges(pollingBox).length, 0);
pollGroups();
console.log('Empty-group dashboard warnings update on failure, successful tests and controller recovery');

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
for (const mode of ['config', 'name-asc', 'name-desc', 'delay-asc', 'delay-desc']) { assert(indexView.includes('option value="' + mode + '"')); }
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

// Delay order changes only presentation and uses the existing exact group data.
const lastRecorded = [{name: 'Latency', members: [
    {name: 'old-timeout', delay: 0}, {name: 'fast-a', delay: 15}, {name: 'untested', delay: null},
    {name: 'slow', delay: 90}, {name: 'bad negative', delay: -1}, {name: 'fast-b', delay: 15},
    {name: 'bad string', delay: '2'}, {name: 'bad NaN', delay: NaN}, {name: 'bad infinity', delay: Infinity}
].map(Object.freeze)}];
lastRecorded.forEach(group => { Object.freeze(group.members); Object.freeze(group); });
Object.freeze(lastRecorded);
const latencyOriginalOrder = lastRecorded[0].members.map(member => member.name);
const unknownLatency = ['old-timeout', 'untested', 'bad negative', 'bad string', 'bad NaN', 'bad infinity'];
const latencyFavorite = new UI.ProxyFavorites(() => null);
latencyFavorite.toggle('proxies', 'old-timeout');
latencyFavorite.toggle('proxies', 'slow');
const delayLabels = {memberCount: 'Members: %s'};
for (const [mode, ordinary] of [
    ['delay-asc', ['fast-a', 'fast-b', 'slow', ...unknownLatency]],
    ['delay-desc', ['slow', 'fast-a', 'fast-b', ...unknownLatency]]
]) {
    UI.renderProxyGroups(groupBox, lastRecorded, delayLabels, String, () => '', null, mode);
    assert.deepEqual(sortedNames(), ordinary, 'Last delay preserves ties and puts unavailable readings last');
    UI.renderProxyGroups(groupBox, lastRecorded, delayLabels, String, () => '', latencyFavorite, mode);
    assert.deepEqual(sortedNames(), ['slow', 'old-timeout', ...ordinary.filter(name => name !== 'slow' && name !== 'old-timeout')]);
    assert.deepEqual(UI.fullProxyGroupTestNames(lastRecorded, 'Latency', latencyFavorite, mode),
        UI.fullProxyGroupTestNames(lastRecorded, 'Latency', latencyFavorite, 'config'),
        'Selecting a latency order never changes the existing favorite-first probe queue');
}
assert.deepEqual(latencyOriginalOrder, lastRecorded[0].members.map(member => member.name));
pollGroups(sortResponse);
orderBy('delay-asc');
assert.deepEqual(displayedGroups(), ['Z group', 'A group']);
assert.deepEqual(displayedMembers()[0], ['Node 10', 'NODE 2', 'node 2', 'Node 1']);
pollingDoc.activeElement = pollingBox.querySelectorAll('button[data-focus-key]')[2];
const delayFocus = pollingDoc.activeElement.attrs['data-focus-key'];
groupContext.testing = true;
orderBy('delay-desc');
assert.deepEqual(displayedMembers()[0], ['NODE 2', 'Node 10', 'node 2', 'Node 1']);
assert.equal(pollingDoc.activeElement.attrs['data-focus-key'], delayFocus);
assert.equal(testsDisabled, true);
assert.deepEqual(selectedNames(), ['Node 10']);
groupContext.testing = false;
const beforeDelayRecovery = pollingBox.children[0];
pollGroups(sortResponse);
assert.equal(pollingBox.children[0], beforeDelayRecovery);
pollGroups({ready: false});
pollGroups({ready: true, groups: [{name: 'Z group', members: [{name: 'Node 1', delay: 80}, {name: 'Node 10', delay: 20}]}, sortGroups[1]]});
assert.deepEqual(displayedMembers()[0], ['Node 1', 'Node 10'], 'Use refreshed recorded latency after recovery');
orderBy('name-desc');
console.log('Last delay sorting: stable, favorites-first, display-only, polling, focus and recovery passed');

// Automatic switching uses only fresh results and never selects direct/reject or
// a nested policy group. Equal delays keep the current selection.
const autoGroup = {name: 'Group &amp; &lt;one&gt;', type: 'Selector', members: [
    {name: 'slow', type: 'Shadowsocks', selected: true, delay: 1},
    {name: 'fast &amp; &lt;two&gt;', type: 'Trojan', selected: false, delay: 999}
]};
const freshDelays = new Map([['slow', 100], ['fast & <two>', 20]]);
assert.equal(UI.fastestProxy(autoGroup, freshDelays), 'fast & <two>');
assert.equal(UI.fastestProxy(autoGroup, new Map()), null, 'Cached history cannot nominate a winner');
assert.equal(UI.fastestProxy(autoGroup, new Map([['slow', 20], ['fast & <two>', 20]])), null);
for (const invalid of [null, undefined, -1, 0, NaN, Infinity, '10']) {
    assert.equal(UI.fastestProxy(autoGroup, new Map([['fast & <two>', invalid]])), null);
}
assert.equal(UI.fastestProxy(autoGroup, new Map([['slow', -1], ['fast & <two>', 20]])), 'fast & <two>');
for (const type of ['URLTest', 'Fallback', 'LoadBalance', 'Relay', 'Direct', 'Reject', 'RejectDrop', 'Pass', 'Compatible', 'Selector']) {
    const group = {...autoGroup, members: [{name: 'alias', type, selected: false}]};
    assert.equal(UI.fastestProxy(group, new Map([['alias', 1]])), null, type + ' must not be selected');
    if (type !== 'Selector') { assert.equal(UI.fastestProxy({...autoGroup, type}, freshDelays), null); }
}
const reversedTie = {...autoGroup, members: [...autoGroup.members].reverse()};
assert.equal(UI.fastestProxy(reversedTie, new Map([['slow', 20], ['fast & <two>', 20]])), null);

// Execute the actual dashboard event handlers and async callbacks, with controlled
// API responses so races are deterministic and do not require an appliance.
const autoScript = indexView.slice(indexView.indexOf('        let testing = false'),
    indexView.indexOf('        /* ------------------------------------------------------------------ *', indexView.indexOf('        let testing = false')))
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
function autoHarness() {
    const nodes = new Map(), calls = [], gets = [], events = {}, errors = [];
    let refreshes = 0;
    function node(selector) {
        if (typeof selector !== 'string') { return selector; }
        if (!nodes.has(selector)) {
            nodes.set(selector, {checked: true, handlers: {}, label: '',
                prop(key, value) { if (value === undefined) { return this[key]; } this[key] = value; return this; },
                on(event, delegate, handler) { this.handlers[handler ? delegate : event] = handler || delegate; return this; },
                text(value) { this.label = value; return this; }, empty() { this.label = ''; return this; }});
        }
        return nodes.get(selector);
    }
    const context = vm.createContext({MihomoUI: UI, latestGroups: {ready: true, groups: [autoGroup]}, favorites: null, nodeOrder: 'config', updateTestAll() {}, $: node,
        document: {hidden: false, addEventListener: (event, handler) => { events[event] = handler; }},
        window: {addEventListener: (event, handler) => { events[event] = handler; }},
        ajaxCall: (url, params, done) => calls.push({url, params, done}),
        ajaxGet: (url, params, done) => gets.push({url, params, done}),
        groupsPoller: {refresh: () => { refreshes++; }}, actionFailed: result => errors.push(result)});
    vm.runInContext(autoScript, context);
    const toggle = enabled => { node('#proxy-autoswitch').checked = enabled; node('#proxy-autoswitch').handlers.change(); };
    const start = (groupName = 'Group & <one>') => {
        context.testGroupName = groupName;
        vm.runInContext('testNodes(["slow", "fast & <two>"], testGroupName);', context);
    };
    const completeTests = () => calls.filter(call => call.url.endsWith('test_delay'))
        .forEach(call => call.done({status: 'ok', delay: freshDelays.get(call.params.name)}, 'success'));
    const validate = (groups = [autoGroup], status = 'success', ready = true) => gets.at(-1).done({ready, groups}, status);
    const writes = () => calls.filter(call => call.url.endsWith('select_proxy'));
    const manual = () => node('#proxy-groups').handlers['.cmd-select'].call({closest: () => ({attr: key => key === 'data-group' ? 'Group & <one>' : 'slow'})});
    return {node, calls, gets, events, context, errors, toggle, start, completeTests, validate, writes, manual, refreshes: () => refreshes};
}
assert(!/id="proxy-autoswitch"[^>]*\bchecked\b/.test(indexView), 'HTML must default off');
let auto = autoHarness();
assert.equal(auto.node('#proxy-autoswitch').checked, false, 'Even restored browser form state defaults off');
auto.start(); auto.completeTests();
assert.equal(auto.gets.length, 0); assert.equal(auto.writes().length, 0); assert.equal(auto.refreshes(), 1);
auto = autoHarness(); auto.toggle(true); auto.start(); auto.start();
assert.equal(auto.calls.length, 2, 'Repeated clicks cannot overlap a test run');
auto.completeTests();
assert.equal(auto.gets.length, 1); assert.equal(auto.writes().length, 0, 'Revalidate before writing');
auto.start(); assert.equal(auto.calls.length, 2, 'Validation remains part of the busy operation');
auto.validate();
assert.equal(auto.writes().length, 1);
assert.deepEqual(JSON.parse(JSON.stringify(auto.writes()[0].params)), {group: 'Group & <one>', member: 'fast & <two>'});
auto.manual(); auto.start(); assert.equal(auto.writes().length, 1, 'No competing writes while automatic selection is in flight');
auto.writes()[0].done({status: 'ok'}, 'success');
assert(auto.node('#proxy-autoswitch-state').label.includes('Group & <one> → fast & <two>'));
assert.equal(auto.refreshes(), 1);
assert.equal(auto.node('#proxy-groups .cmd-select').disabled, false);

for (const cancel of [
    h => { h.toggle(false); h.toggle(true); },
    h => { h.context.document.hidden = true; h.events.visibilitychange(); h.context.document.hidden = false; },
    h => h.events.pagehide(),
    h => { h.manual(); h.writes()[0].done({status: 'ok'}, 'success'); }
]) {
    for (const duringValidation of [false, true]) {
        const h = autoHarness(); h.toggle(true); h.start();
        if (duringValidation) { h.completeTests(); }
        cancel(h);
        if (duringValidation) { h.validate(); } else { h.completeTests(); }
        assert(h.writes().every(call => call.params.member === 'slow'), 'Cancellation must suppress the automatic write');
        assert(h.node('#proxy-autoswitch-state').label.includes('skipped'));
    }
}
for (const response of [
    [], [{...autoGroup, type: 'URLTest'}],
    [{...autoGroup, members: autoGroup.members.slice(0, 1)}],
    [{...autoGroup, members: autoGroup.members.map(member => ({...member, selected: !member.selected}))}]
]) {
    const h = autoHarness(); h.toggle(true); h.start(); h.completeTests(); h.validate(response);
    assert.equal(h.writes().length, 0, 'Changed group state must cancel');
    assert.equal(h.refreshes(), 1);
}
for (const [status, ready] of [['error', true], ['success', false]]) {
    const h = autoHarness(); h.toggle(true); h.start(); h.completeTests(); h.validate([autoGroup], status, ready);
    assert.equal(h.writes().length, 0);
}
auto = autoHarness(); auto.toggle(true); auto.start();
auto.calls.forEach(call => call.done({status: 'failed', delay: 10}, 'success'));
assert.equal(auto.gets.length, 0); assert.equal(auto.writes().length, 0, 'No winner on failed probes');
auto = autoHarness(); auto.start(); auto.toggle(true); auto.completeTests();
assert.equal(auto.gets.length, 0, 'Opting in mid-run cannot authorize a switch');
auto = autoHarness(); auto.toggle(true); auto.start(null); auto.completeTests();
assert.equal(auto.gets.length, 0, 'Individual node tests never switch groups');
auto = autoHarness(); auto.toggle(true);
auto.context.latestGroups = {ready: true, groups: [{...autoGroup, type: 'URLTest'}]};
auto.start(); auto.completeTests(); assert.equal(auto.gets.length, 0);
auto = autoHarness(); auto.toggle(true); auto.start(); auto.completeTests(); auto.validate();
auto.writes()[0].done({status: 'failed'}, 'success');
assert.equal(auto.errors.length, 1); assert.equal(auto.refreshes(), 1);
assert.equal(auto.writes().length, 1, 'Failed writes are reported without retry');
assert.equal(auto.node('#proxy-autoswitch-state').label, '', 'Failed writes must not claim a switch');
// Real delegated group button carries the group name, not just the test names.
auto = autoHarness(); auto.toggle(true);
auto.node('#proxy-groups').handlers['.cmd-test-group'].call({
    attr: () => 'Group & <one>',
    closest: () => ({find: () => ({each: callback => ['slow', 'fast & <two>', 'slow'].forEach(name => callback.call({attr: () => name}))})})
});
assert.equal(auto.calls.length, 2, 'Group probes are deduplicated');
auto.completeTests(); auto.validate(); assert.equal(auto.writes().length, 1);
console.log('Experimental automatic switching: default-off, fresh minimum, exclusions, ties, cancellation, revalidation and failures passed');

// An explicit reset clears a core override; sorting/favorites never supply a target member.
const resetName = ' 中文 /?%#" <tag> &gt; ';
const resetResponse = {ready: true, groups: [
    {name: encode(resetName), type: 'URLTest', canReset: true, members: [{name: 'First'}, {name: 'Pinned', selected: true}]},
    {name: 'Fallback', type: 'Fallback', canReset: true, members: [{name: 'Pinned', selected: true}]},
    {name: 'Automatic', type: 'URLTest', canReset: false, members: [{name: 'First', selected: true}]},
    {name: 'Selector', type: 'Selector', canReset: false, members: [{name: 'First', selected: true}]},
    {name: 'Legacy', type: 'URLTest', members: [{name: 'First', selected: true}]}
]};
pollGroups(resetResponse);
const resetButtons = () => pollingBox.querySelectorAll('button[data-group]').filter(node => node.attrs.class.includes('cmd-reset-group'));
const selectButtons = () => pollingBox.querySelectorAll('button[data-focus-key]').filter(node => node.attrs.class.includes('cmd-select'));
assert.deepEqual(resetButtons().map(node => node.attrs['data-group']), [resetName, 'Fallback']);
assert.equal(resetButtons()[0].attrs['aria-label'], 'Resume automatic selection: ' + resetName);
assert.equal(resetButtons()[0].attrs.type, 'button');
assert.equal(resetButtons()[0].textContent, 'Resume automatic selection');
assert(!Object.hasOwn(resetButtons()[0].attrs, 'data-unexpected'));
const resetActionScript = indexView.match(/        function changeSelection\(action, params\) \{[\s\S]*?(?=\n        function loadGroups)/)[0];
vm.runInContext(resetActionScript, groupContext);
selectionHandlers['.cmd-reset-group'].call(resetButtons()[0]);
assert.equal(selectionRequests.length, 1);
assert.equal(selectionRequests[0].url, '/api/mihomo/dashboard/reset_proxy');
assert.deepEqual(JSON.parse(JSON.stringify(selectionRequests[0].params)), {group: resetName});
assert(selectionDisabled);
selectionHandlers['.cmd-reset-group'].call(resetButtons()[0]);
selectionHandlers['.cmd-select'].call(selectButtons()[0]);
assert.equal(selectionRequests.length, 1, 'Pending reset blocks repeated resets and competing manual selection');
resetResponse.groups[0].members[0].delay = 10;
selectionDisabled = false;
pollGroups(resetResponse);
assert(selectionDisabled, 'A polling redraw keeps selection controls disabled while reset is pending');
const beforeResetSelection = selectedNames();
selectionRequests[0].done({status: 'failed', message: 'Core rejected reset'}, 'success');
assert(!selectionDisabled);
assert.equal(selectionFailures, 1);
assert.equal(selectionRefreshes, 0);
assert.deepEqual(selectedNames(), beforeResetSelection, 'Failed reset never fabricates a selection');
selectionHandlers['.cmd-reset-group'].call(resetButtons()[0]);
selectionRequests[1].done(null, 'error');
assert.equal(selectionFailures, 2, 'Transport failure is visible and retryable');
assert(!selectionDisabled);
selectionHandlers['.cmd-reset-group'].call(resetButtons()[0]);
selectionRequests[2].done({status: 'ok'}, 'success');
assert.equal(selectionRefreshes, 1, 'Successful reset fetches the core-selected member');
assert.equal(clearedActions, 1);
assert(!selectionDisabled);
assert.deepEqual(selectedNames(), beforeResetSelection, 'Reset does not guess the first or fastest member');
resetResponse.groups[0].canReset = false;
pollGroups(resetResponse);
assert.deepEqual(resetButtons().map(node => node.attrs['data-group']), ['Fallback'], 'Cleared overrides disappear after refresh');
selectionHandlers['.cmd-select'].call(selectButtons().find(button => pollingBox.querySelectorAll('li[data-member]')
    .some(node => node.attrs['data-member'] === 'First' && node.contains(button))));
assert.equal(selectionRequests[3].url, '/api/mihomo/dashboard/select_proxy');
assert.deepEqual(JSON.parse(JSON.stringify(selectionRequests[3].params)), {group: resetName, member: 'First'});
selectionHandlers['.cmd-reset-group'].call(resetButtons()[0]);
assert.equal(selectionRequests.length, 4, 'Pending manual selection also blocks reset');
selectionRequests[3].done({status: 'ok'}, 'success');
assert.equal(selectionRefreshes, 2);
console.log('Automatic selection reset: eligibility, safe names, pending redraws, failures, retry and refresh passed');

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

// Search is local and does not change selected proxies or group probe scope.
const filterSource = {ready: true, groups: [{name: 'Search group', now: 'Other', members: [
    {name: 'ZA &amp; Zurich', selected: false}, {name: 'Other', selected: true},
    {name: 'ZA [a.*]', selected: false}, {name: '中文节点', selected: false}, {name: 'literal &amp;gt;', selected: false}
]}, {name: 'Second group', members: [{name: 'ZA &amp; Zurich'}]}, {name: 'Empty group', members: []}]};
const beforeFilter = JSON.stringify(filterSource);
const filter = value => proxyFilterControl.val(value).trigger('input');
const shownNames = () => pollingBox.querySelectorAll('li[data-member]').map(node => node.attrs['data-member']);
let filterRequests = 0;
groupContext.ajaxCall = groupContext.ajaxGet = () => { filterRequests++; };
pollGroups(filterSource);
filter(' ZA ');
assert.equal(proxyFilterStatus, 'Visible proxy entries: 3/6');
assert.equal(shownNames().length, 3);
assert(!displayedGroups().includes('Empty group'));
assert(!pollingBox.querySelectorAll('li[data-member]').some(node => node.attrs.class.includes(' active')));
const beforeUnchanged = pollingBox.children[0];
pollGroups(filterSource);
filter('za');
assert.equal(pollingBox.children[0], beforeUnchanged, 'Equivalent filters and unchanged polls preserve DOM');
const wholeGroup = pollingBox.querySelectorAll('button[data-group]').find(button =>
    button.attrs.class.includes('cmd-test-group') && button.attrs['data-group'] === 'Search group');
nodeOrderHandler.call({value: 'name-asc'});
dashboardFavorites.toggle('proxies', 'Other');
testGroupHandler.call(wholeGroup);
assert.deepEqual(foldedTestNames, ['Other', ...['literal &gt;', 'ZA [a.*]', 'ZA & Zurich', '中文节点'].sort(new Intl.Collator(undefined, {numeric: true, sensitivity: 'base'}).compare)],
    'Filtered groups still probe every exact name in prior natural/favorite order');
for (const mode of ['delay-asc', 'delay-desc']) {
    nodeOrderHandler.call({value: mode});
    testGroupHandler.call(wholeGroup);
    assert.deepEqual(foldedTestNames, ['Other', 'ZA & Zurich', 'ZA [a.*]', '中文节点', 'literal &gt;'],
        'Latency sorting and a filter cannot change full-group configured/favorite probe scope or queue order');
}
nodeOrderHandler.call({value: 'name-asc'});
filter('[a.*]');
assert.deepEqual(shownNames(), ['ZA [a.*]']);
filter('&gt;');
assert.deepEqual(shownNames(), ['literal &gt;']);
filter('中文节');
assert.deepEqual(shownNames(), ['中文节点']);
filter('Search group');
assert.deepEqual(shownNames(), []);
assert.equal(proxyFilterStatus, 'Visible proxy entries: 0/6');
assert.equal(pollingBox.children[0].textContent, 'No proxy names match the filter.');
filter('ZA');
groupContext.testing = true;
filter('Zurich');
assert.equal(testsDisabled, true, 'New controls remain disabled during in-flight latency tests');
groupContext.testing = false;
pollGroups({ready: false});
filter('ZA');
assert.deepEqual(shownNames(), [], 'Filtering never revives a stale group snapshot');
assert.equal(proxyFilterStatus, '');
pollGroups(filterSource);
assert.equal(shownNames().length, 3);
proxyFilterClear();
assert.equal(shownNames().length, 6);
assert(proxyFilterControl.focused);
assert.equal(proxyFilterStatus, '');
assert.equal(JSON.stringify(filterSource), beforeFilter);
assert.equal(filterRequests, 0);
assert(wholeGroup.attrs['aria-label'].startsWith('Test all nodes'));
console.log('Proxy name filter: Unicode/literal text, counts, polling and unchanged full-group probes passed');

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
    connectionAddressCell() {}, // The formatter itself is exercised separately below.
    $: selector => {
        if (selector === '#grid-connections') { return connectionGrid; }
        if (selector === '#connection-visible-count') {
            return {text: value => { visibleConnectionCount = value; }};
        }
        if (selector === '[data-toggle="tooltip"]') { return {tooltip: () => {}}; }
        if (selector === '#grid-connections tbody .cmd-close-connection') { return {each() {}}; }
        if (selector.startsWith('#close-')) { return {prop() {}, on() {}}; }
        if (selector === '#connection-search-scope') { return {change() {}}; }
        assert(['.cmd-close-connection', '.cmd-connection-details'].includes(selector));
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
const networkViewFixture5 = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/network_status.volt'), 'utf8');
const networkScript = networkViewFixture5.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
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
    assert(networkViewFixture5.includes('class="network-copy-state text-muted" role="status" aria-live="polite"'));
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

const contextFilter = ['level=error msg="at zero"', 'level=info msg="a"', 'level=info msg="b"',
    'level=error msg="nearby, but outside radius"', 'level=error msg="hit"', 'level=error msg="context"',
    'level=info msg="hit wrong severity"'];
const errorOnly = line => logLevel(line) === 'error';
assert.deepEqual(filterLogLines(contextFilter, 'hit', 2, errorOnly), {
    lines: contextFilter.slice(3, 6), matches: 1
}, 'Context measures original offsets and does not reintroduce other severities');

// Run the actual connection formatter and delegated click handler. DOM values
// remain text/attributes even when controller strings contain markup or quotes.
const addressScript = indexView.match(/        function isCopyAddressText\(text\) \{[\s\S]*?(?=        function showConnectionDetails\(row\))/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
const copyControls = new Map();
let addressClick, dismissAddress, renderedCell;
function copyControl(selector) {
    if (!copyControls.has(selector)) {
        copyControls.set(selector, {value: '', label: '', hidden: true, focused: false, selected: false,
            0: null, text(value) { this.label = value; return this; },
            val(value) { this.value = value; return this; },
            prop(key, value) { this[key] = value; return this; },
            focus() { this.focused = true; return this; },
            select() { this.selected = true; return this; }});
    }
    const control = copyControls.get(selector);
    control[0] = control;
    return control;
}
const copyContext = {
    document: {createElement(tag) {
        const node = doc.createElement(tag);
        // Capture the real DOM tree immediately before Bootgrid serialization.
        Object.defineProperty(node, 'outerHTML', {get() { renderedCell = this; return 'serialized cell'; }});
        return node;
    }},
    MihomoUI: UI, navigator: {},
    $: selector => selector === '#grid-connections' ? {on(event, selector, fn) {
        assert.equal(event, 'click'); assert.equal(selector, '.cmd-copy-address'); addressClick = fn;
    }} : selector === '#connection-copy-dismiss' ? {on(event, fn) {
        assert.equal(event, 'click'); dismissAddress = fn;
    }} : copyControl(selector)
};
vm.createContext(copyContext);
vm.runInContext(addressScript, copyContext);
assert(indexView.includes("'addressformatter': connectionAddressCell"));
for (const column of ['source', 'host']) {
    assert.match(indexView, new RegExp('<th data-column-id="' + column + '"[^>]+data-formatter="addressformatter"'));
}
assert.match(indexView, /id="connection-copy-state"[^>]+role="status"/);
assert.match(indexView, /id="connection-copy-value"[^>]+readonly/);
const addressRow = {host: encode('<host>&amp;"'), source: '192.0.2.8:50000',
    sourceIP: '192.0.2.8', destinationIP: '2001:db8::9'};
function renderAddress(id, row = addressRow) {
    assert.equal(copyContext.connectionAddressCell({id}, row), 'serialized cell');
    return renderedCell;
}
const sourceCell = renderAddress('source');
assert.equal(sourceCell.textContent, addressRow.source);
const sourceCopy = sourceCell.children[0];
assert.equal(sourceCopy.attrs['data-address'], '192.0.2.8');
assert.equal(sourceCopy.attrs['aria-label'], 'Copy source IP address: 192.0.2.8');
const hostCell = renderAddress('host'), destinationCopy = hostCell.children[0];
assert.equal(hostCell.textContent, '<host>&amp;"', 'Decode display text exactly once');
assert.equal(destinationCopy.attrs['data-address'], '2001:db8::9');
assert.equal(destinationCopy.attrs.title, 'Copy destination IP address: 2001:db8::9');
for (const button of [sourceCopy, destinationCopy]) {
    assert.equal(button.attrs.type, 'button', 'Native keyboard activation');
    assert.equal(button.children[0].attrs['aria-hidden'], 'true');
}
for (const missing of [undefined, null, '']) {
    assert.equal(renderAddress('host', {...addressRow, destinationIP: missing}).children.length, 0);
    assert.equal(renderAddress('source', {...addressRow, sourceIP: missing}).children.length, 0);
}
const hostileAddress = '" data-unexpected="x<>&amp;';
assert.equal(renderAddress('host', {...addressRow, destinationIP: encode(hostileAddress)}).children.length, 0);
assert.equal(renderAddress('source', {...addressRow, sourceIP: '2001:db8::8'}).children[0].attrs['data-address'], '2001:db8::8');
const copyState = copyControl('#connection-copy-state'), manualCopy = copyControl('#connection-copy-manual');
const copyValue = copyControl('#connection-copy-value');
let stoppedCopies = 0;
const clickAddress = button => addressClick.call(button, {stopPropagation() { stoppedCopies++; }});
(async () => {
    const copied = [];
    let finishCopy;
    copyContext.navigator.clipboard = {writeText(value) { copied.push(value); return new Promise(resolve => { finishCopy = resolve; }); }};
    const pending = clickAddress(destinationCopy);
    assert.deepEqual(copied, ['2001:db8::9'], 'Write starts directly in the click gesture, using metadata rather than hostname');
    assert.equal(copyState.label, '', 'Never claim success before the clipboard resolves');
    finishCopy(); await pending;
    assert.equal(copyState.label, 'IP address copied.');
    assert.equal(manualCopy.hidden, true);
    for (const clipboard of [undefined, {}, {writeText() { throw new Error('Unavailable'); }},
        {writeText() { return Promise.reject(new Error('Permission denied')); }}]) {
        copyContext.navigator.clipboard = clipboard;
        await clickAddress(sourceCopy);
        assert.equal(copyState.label, 'Clipboard unavailable. Copy the selected IP address manually.');
        assert.equal(manualCopy.hidden, false);
        assert.equal(copyValue.value, '192.0.2.8');
        assert(copyValue.focused && copyValue.selected);
    }
    copyContext.navigator.clipboard = {writeText(value) { copied.push(value); return Promise.resolve(); }};
    // A new button after table reload needs no new handler registration.
    const refreshedButton = renderAddress('source', {...addressRow, sourceIP: '2001:db8::10'}).children[0];
    await clickAddress(refreshedButton);
    assert.equal(copied.at(-1), '2001:db8::10');
    assert.equal(copyState.label, 'IP address copied.');
    assert.equal(manualCopy.hidden, true);
    assert.equal(copyValue.value, '');
    let rejectOldCopy;
    copyContext.navigator.clipboard = {writeText() { return new Promise((resolve, reject) => { rejectOldCopy = reject; }); }};
    const oldCopy = clickAddress(sourceCopy);
    copyContext.navigator.clipboard = {writeText() { return Promise.resolve(); }};
    await clickAddress(destinationCopy);
    rejectOldCopy(new Error('Late failure')); await oldCopy;
    assert.equal(copyState.label, 'IP address copied.', 'An old failure cannot replace the latest result');
    assert.equal(manualCopy.hidden, true);
    copyContext.navigator.clipboard = undefined;
    await clickAddress(sourceCopy);
    assert.equal(manualCopy.hidden, false);
    dismissAddress();
    assert.equal(manualCopy.hidden, true);
    assert.equal(copyValue.value, '');
    assert.equal(copyState.label, '');
    copyContext.navigator.clipboard = {writeText() { return new Promise((resolve, reject) => { rejectOldCopy = reject; }); }};
    const dismissPending = clickAddress(sourceCopy);
    dismissAddress();
    rejectOldCopy(new Error('Dismissed attempt')); await dismissPending;
    assert.equal(copyState.label, '');
    assert.equal(manualCopy.hidden, true);
    assert.equal(stoppedCopies, 10);
    console.log('Connection copy UI: IPv4/IPv6, safe DOM, missing IPs, reloads, clipboard success/failure, dismissible fallback and stale results passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

// Read-only aggregate from the existing successful poll, independent of row filters.
const summaryRows = [
    {name: 'A', members: [{name: 'Shared', type: 'VLESS', delay: 19},
        {name: 'Zero', type: 'SS', delay: 0}, {name: 'Negative', type: 'SS', delay: -1},
        {name: 'Unknown', type: 'VLESS', delay: null}, {name: 'Malformed delay', type: 'VLESS', delay: '55'},
        {name: 'Fraction', type: 'VLESS', delay: 1.1}, {name: 'Infinite', type: 'VLESS', delay: Infinity},
        {name: 'Dangling', type: '', delay: null},
        {name: 'Nested', type: 'Selector', delay: 3}, {name: 'Omitted group', type: 'URLTest', delay: 4},
        {name: 'DIRECT', type: 'Direct', delay: 2}, {name: 'REJECT', type: 'Reject', delay: 0},
        {name: 'REJECT-DROP', type: 'RejectDrop', delay: 0}, {name: 'PASS', type: 'Pass', delay: 1}]},
    {name: 'Nested', members: [{name: 'Shared', type: 'VLESS', delay: 19}]}
];
assert.deepEqual(UI.summarizeProxyLatency(summaryRows), {responding: 1, noPositive: 2, unknown: 5});
assert.deepEqual(UI.summarizeProxyLatency([]), {responding: 0, noPositive: 0, unknown: 0});
for (const bad of [undefined, null, {}, [null], [{name: 'Bad'}], [{name: 'Bad', members: [null]}]]) {
    assert.equal(UI.summarizeProxyLatency(bad), null, 'Malformed projections must not become zero counts');
}
const summaryHandler = indexView.match(/        function loadGroups\(done\) \{[\s\S]*?\n        \}/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, msg) => JSON.stringify(msg));
let summaryStatus = 'Loading …', summaryWrites = 0, groupWrites = 0, summaryRequests = 0, saidDone;
const summaryContext = vm.createContext({
    selecting: false, snapshotBusy: false, groupsRevision: 0, autoTestEnabled: false, updateTestAll() {},
    testing: false, MihomoUI: UI, fmtCount: String,
    ajaxGet(path, args, done) {
        assert.equal(path, '/api/mihomo/dashboard/proxies');
        assert.equal(Object.keys(args).length, 0);
        summaryRequests++;
        done(summaryContext.response, summaryContext.status);
    },
    renderGroups() { groupWrites++; },
    $: selector => selector === '#proxy-health-summary' ? {text(value) {
        if (typeof value === 'undefined') { return summaryStatus; }
        summaryStatus = value; summaryWrites++;
    }} : {text() {}},
    done: status => { saidDone = status; }
});
vm.runInContext(summaryHandler, summaryContext);
function summaryPoll(response, status) {
    summaryContext.response = response;
    summaryContext.status = status;
    vm.runInContext('loadGroups(done);', summaryContext);
}
const validSummary = {ready: true, groups: summaryRows};
summaryPoll(validSummary, 'success');
assert.equal(summaryStatus, 'Responding: 1 · No positive result: 2 · Untested or unknown: 5');
assert.equal(saidDone, true);
summaryPoll(validSummary, 'success');
assert.equal(summaryWrites, 1, 'Unchanged live-region text is not announced every poll');
summaryPoll(validSummary, 'error');
assert.equal(summaryStatus, 'Status unavailable');
assert.equal(saidDone, false);
assert.equal(groupWrites, 2, 'Transport failure retains the existing group rows');
summaryPoll({ready: true}, 'success');
assert.equal(summaryStatus, 'Status unavailable');
assert.equal(saidDone, true, 'Summary validity does not change the original poll success result');
assert.equal(groupWrites, 3, 'A successful response still uses the original group rendering path');
summaryPoll({ready: false, groups: []}, 'success');
assert.equal(summaryStatus, 'Status unavailable');
assert.equal(saidDone, false);
summaryPoll({ready: true, groups: []}, 'success');
assert.equal(summaryStatus, 'Responding: 0 · No positive result: 0 · Untested or unknown: 0');
assert.equal(saidDone, true);
summaryPoll(validSummary, 'success');
assert.equal(summaryStatus, 'Responding: 1 · No positive result: 2 · Untested or unknown: 5');
assert.equal(summaryRequests, 7, 'Only the existing one-request poll is used');
summaryContext.testing = true;
summaryPoll(validSummary, 'success');
assert.equal(summaryRequests, 7, 'Busy group tests still pause polling');
console.log('Proxy latency summary: deduplication, unknown values, failed reads, true empty results and request isolation passed');

// Hide is only a projection of the existing full snapshot and exact display names.
{
    const hiddenDoc = {activeElement: null, createElement(tag) { return new DomNode(this, tag); }};
    hiddenDoc.createElementNS = (_, tag) => hiddenDoc.createElement(tag);
    const hiddenBox = hiddenDoc.createElement('div');
    const exactHiddenName = 'Alpha &gt; <visible> 中文"';
    const fixtureNode = (name, selected = false, delay = 20) =>
        ({name: encode(name), selected, type: 'fake', delay});
    const hiddenFixture = {ready: true, groups: [
        {name: 'A', now: 'Selected', type: 'Selector', members: [fixtureNode(exactHiddenName), fixtureNode('Selected', true), fixtureNode('Archive')]},
        {name: 'B', now: encode(exactHiddenName), type: 'Selector', members: [fixtureNode(exactHiddenName, true)]},
        {name: 'C', now: '', type: 'Selector', members: [fixtureNode(exactHiddenName)]},
        {name: 'Empty', now: '', type: 'Selector', members: []}
    ]};
    const hiddenCopy = JSON.stringify(hiddenFixture);
    const controls = new Map(), hideHandlers = new Map();
    const controlFor = key => {
        if (!controls.has(key)) {
            const c = {value: '', checked: true, handlers: {}, disabled: false, focused: false, disabledTests: false,
                on(event, handler) { this.handlers[event] = handler; return this; },
                empty() { this.value = ''; },
                val(value) { this.value = value; return this; },
                text(value) { this.value = value; return this; },
                prop(key, value) { this[key] = value; return this; },
                trigger(event) { if (event === 'focus') { this.focused = true; } else { this.handlers[event].call(this); } return this; }};
            controls.set(key,c);
        }
        return controls.get(key);
    };
    let hiddenProbes, hiddenNetwork = 0;
    const hiddenVM = vm.createContext({
        proxyNotes: null, selecting: false,
        $: selector => {
            if (selector === '#proxy-groups') {
                return {0: hiddenBox, on: (event, target, handler) => { assert.equal(event, 'click'); hideHandlers.set(target, handler); },
                    html: text => { const n = hiddenDoc.createElement('placeholder'); n.textContent = text; hiddenBox.replaceChildren(n); }};
            }
            if (selector instanceof DomNode) { return {attr: key => selector.getAttribute(key)}; }
            return controlFor(selector);
        },
        fmtCount: String, MihomoUI: UI, favorites: null, nodeOrder: 'config', latestGroups: null, testing: false,
        delayText: String, delayClass: () => 'label-success', testNodes: names => { hiddenProbes = Array.from(names); },
        ajaxCall() { hiddenNetwork++; }, ajaxGet() { hiddenNetwork++; }
    });
    const visibilityScript = indexView.match(/        function updateProxyVisibility\(\) \{[\s\S]*?(?=        let testing = false;)/)[0];
    vm.runInContext(collapseStateScript + '\n' + renderGroupsScript + '\n' + visibilityScript + '\n' + testGroupScript, hiddenVM);
    assert.equal(controlFor('#proxy-show-hidden').checked, false, 'Reset restored form checkbox on a fresh load');
    const boxMembers = () => hiddenBox.querySelectorAll('li[data-member]').map(n => [n.getAttribute('data-group'), n.getAttribute('data-member')]);
    const getHide = (group, name) => hiddenBox.querySelectorAll('button[data-focus-key]').find(n =>
        n.getAttribute('data-focus-key') === JSON.stringify(['visibility', group, name]));
    const getProbe = group => hiddenBox.querySelectorAll('button[data-focus-key]').find(n =>
        n.getAttribute('data-focus-key') === JSON.stringify(['group', group]));
    const getGroupList = group => hiddenBox.querySelectorAll('ul[data-group]').find(n => n.getAttribute('data-group') === group);
    hiddenVM.response = hiddenFixture;
    vm.runInContext('renderGroups(response);', hiddenVM);
    assert.equal(getHide('B', exactHiddenName), undefined, 'Do not offer hiding the currently selected occurrence');
    const oldHideButton = getHide('A', exactHiddenName);
    assert.equal(oldHideButton.getAttribute('title'), 'Hide proxy until reload');
    hiddenDoc.activeElement = oldHideButton;
    hideHandlers.get('.cmd-hide-proxy').call(oldHideButton);
    assert.deepEqual(boxMembers(), [['A','Selected'],['A','Archive'],['B',exactHiddenName]], 'Hide exact names except selected occurrences');
    assert.equal(hiddenDoc.activeElement.getAttribute('data-focus-key'), JSON.stringify(['collapse','A']), 'Move focus to the retained group after its button disappears');
    assert.equal(getGroupList('C').children[0].textContent, 'All matching proxies in this group are hidden.');
    assert.equal(getGroupList('Empty').children.length, 0, 'Genuine empty groups do not show a hidden message');
    assert.equal(controlFor('#proxy-hidden-count').value, '1');
    assert.equal(JSON.stringify(hiddenFixture), hiddenCopy, 'No snapshot mutation');
    hideHandlers.get('.cmd-test-group').call(getProbe('C'));
    assert.deepEqual(hiddenProbes, [exactHiddenName], 'A group with all members hidden still probes the full preexisting scope when explicitly clicked');
    const hiddenRoot = hiddenBox.children[0];
    vm.runInContext('renderGroups(response);', hiddenVM);
    assert.equal(hiddenBox.children[0], hiddenRoot, 'Repeated identical poll keeps current DOM');
    const filter = controlFor('#proxy-filter');
    filter.value = 'archive';
    filter.handlers.input.call(filter);
    assert.deepEqual(boxMembers(), [['A','Archive']], 'The existing name filter remains independent');
    assert.equal(controlFor('#proxy-filter-state').value, 'Name matches before hiding: 1/5');
    filter.value = 'missing';
    filter.handlers.input.call(filter);
    assert.equal(hiddenBox.children[0].textContent, 'No proxy names match the filter.');
    filter.value = '';
    filter.handlers.input.call(filter);
    const eye = controlFor('#proxy-show-hidden');
    eye.checked = true;
    eye.handlers.change.call(eye);
    assert(boxMembers().some(([group,name]) => group === 'C' && name === exactHiddenName), 'Reveal hidden proxies without changing the hidden set');
    assert.equal(getHide('A', exactHiddenName).getAttribute('title'), 'Restore proxy');
    hideHandlers.get('.cmd-hide-proxy').call(getHide('A', exactHiddenName));
    assert.equal(controlFor('#proxy-hidden-count').value, '0');
    eye.checked = false;
    eye.handlers.change.call(eye);
    hideHandlers.get('.cmd-hide-proxy').call(getHide('A', exactHiddenName));
    const restoreAll = controlFor('#proxy-restore-all');
    restoreAll.handlers.click.call(restoreAll);
    assert.equal(controlFor('#proxy-hidden-count').value, '0');
    assert(restoreAll.disabled && eye.focused, 'Restore all keeps focus on a reachable control');
    assert.equal(hiddenNetwork, 0, 'The new controls neither issue requests nor run automatic probes');
    console.log('Proxy temporary hiding: exact names, selected entries, independent filtering, focus and unchanged group probe scope passed');
}

// Run the dashboard's actual batch/stop handlers with delayed API responses.
const stopButtonMarkup = indexView.match(/<button[^>]*id="stop-proxy-tests"[^>]*>/)[0];
assert(stopButtonMarkup.includes('type="button"') && stopButtonMarkup.includes(' disabled'),
    'Stop is a native keyboard button, disabled until a batch starts');
assert(stopButtonMarkup.includes('aria-describedby="proxy-test-state"'));
const probeRequests = [], probeControls = new Map();
let probeRefreshes = 0;
function probeControl(selector) {
    if (typeof selector !== 'string') { return selector; }
    if (!probeControls.has(selector)) {
        probeControls.set(selector, {disabled: true, label: '',
            empty() { this.label = ''; return this; },
            prop(key, value) { this[key] = value; return this; },
            text(value) { this.label = value; return this; },
            on(event, handler) { assert.equal(event, 'click'); this.click = handler; return this; }});
    }
    return probeControls.get(selector);
}
const probeContext = vm.createContext({
    selecting: false, snapshotBusy: false, autoSwitchGeneration: 0, $autoSwitch: {prop: () => false},
    updateTestAll() {}, cancelAutoSwitch() {},
    $: probeControl, MihomoUI: UI,
    ajaxCall: (url, data, done) => {
        assert.equal(url, '/api/mihomo/dashboard/test_delay');
        probeRequests.push({name: data.name, done});
    },
    groupsPoller: {refresh() { probeRefreshes++; }}
});
const probeScript = indexView.match(/        function testNodes\(names(?:,[^)]*)?\) \{[\s\S]*?(?=        \$\('#proxy-groups'\)\.on\('click', '\.cmd-test',)/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
vm.runInContext('let testing = false; let latencyBatch = null;\n' + probeScript, probeContext);
const stopProbes = probeControl('#stop-proxy-tests');
const probeStatus = probeControl('#proxy-test-state');
const testButtons = probeControl('#proxy-groups .cmd-test, #proxy-groups .cmd-test-group');
stopProbes.click();
vm.runInContext('testNodes([]);', probeContext);
assert.equal(probeRequests.length, 0);
vm.runInContext('testNodes(["a", "b", "c", "d", "e", "f"]);', probeContext);
assert.equal(stopProbes.disabled, false);
assert.equal(testButtons.disabled, true);
probeRequests[0].done({status: 'ok'}, 'success');
assert.equal(probeRequests.length, 4);
stopProbes.click();
stopProbes.click();
assert.equal(stopProbes.disabled, true);
assert(probeStatus.label.includes('Skipped: 2'));
assert(probeStatus.label.includes('Stopping tests; waiting for active requests.'));
vm.runInContext('testNodes(["overlap"]);', probeContext);
assert.equal(probeRequests.length, 4, 'New batches stay blocked while cancelled requests drain');
probeRequests[1].done(null, 'error');
probeRequests[2].done({status: 'failed'}, 'success');
assert.equal(testButtons.disabled, true);
assert.equal(probeRefreshes, 0);
probeRequests[3].done({status: 'ok'}, 'success');
assert.equal(testButtons.disabled, false);
assert.equal(probeRefreshes, 1, 'Refresh controller results after the last active response');
assert.equal(probeStatus.label, 'Latency tests: 4/6 · Failed: 2 · Skipped: 2 · Tests stopped.');
vm.runInContext('testNodes(["new"]);', probeContext);
assert.equal(stopProbes.disabled, false);
assert.equal(probeStatus.label, 'Latency tests: 0/1 · Failed: 0', 'A new batch clears the stopped summary');
probeRequests[3].done({status: 'ok'}, 'success');
assert.equal(testButtons.disabled, true, 'An old duplicate response cannot finish the new batch');
probeRequests[4].done({status: 'ok'}, 'success');
assert.equal(probeStatus.label, 'Latency tests: 1/1 · Failed: 0');
assert.equal(stopProbes.disabled, true);
assert.equal(testButtons.disabled, false);
assert.equal(probeRefreshes, 2);
// Stopping a single request cannot abort it, but still waits and records its result.
vm.runInContext('testNodes(["single"]);', probeContext);
stopProbes.click();
assert(probeStatus.label.includes('Skipped: 0'));
assert.equal(testButtons.disabled, true);
probeRequests[5].done(null, 'timeout');
assert.equal(probeStatus.label, 'Latency tests: 1/1 · Failed: 1 · Skipped: 0 · Tests stopped.');
assert.equal(probeRefreshes, 3);
console.log('Latency test stopping: queued work, active drain, counts, failures, duplicates, restart and dashboard controls passed');

// Run the real connection controls against rendered-page and delayed-request fixtures.
// Rows outside the current page/search never enter the DOM selection.
const connectionView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/index.volt'), 'utf8');
const visibleConnectionScript = connectionView.slice(connectionView.indexOf('        let closingVisible'),
    connectionView.indexOf('        gTrafficChart ='))
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
assert(visibleConnectionScript.includes('close-visible-connections'), 'The visible-close feature must be present');
assert.match(connectionView, /id="close-visible-connections"[^>]* disabled>/, 'Disabled before the first load');
const connectionControls = new Map(), closeRequests = [], confirmations = [];
let pageButtons = [], reloads = 0, overviewRefreshes = 0, failures = 0, gridOptions;
class ConnectionControl {
    constructor(id) { this.id = id; this.handlers = {}; this.disabled = false; this.label = ''; }
    on(event, handler) { this.handlers[event] = handler; return this; }
    off(event) { delete this.handlers[event]; return this; }
    click(handler) { return this.on('click', handler); }
    change(handler) { return this.on('change', handler); }
    prop(key, value) { this[key] = value; return this; }
    attr(key) { assert.equal(key, 'data-id'); return this.id; }
    text(value) { this.label = value; return this; }
    empty() { this.label = ''; return this; }
    tooltip() { return this; }
    UIBootgrid(options) { gridOptions = options; return this; }
    bootgrid(action) {
        if (action === 'getCurrentRows') { return pageButtons; }
        assert.equal(action, 'reload'); reloads++;
        this.handlers['load.rs.jquery.bootgrid']();
        return this;
    }
}
function connectionControl(selector) {
    if (selector instanceof ConnectionControl) { return selector; }
    if (selector === '#grid-connections tbody .cmd-close-connection') {
        return {each(fn) { pageButtons.forEach(button => fn.call(button)); }};
    }
    if (selector === '.cmd-close-connection' || selector === '#close-all-connections, #grid-connections .cmd-close-connection') {
        const nodes = selector.startsWith('#close-all') ? [connectionControl('#close-all-connections'), ...pageButtons] : pageButtons;
        return {
            prop(key, value) { nodes.forEach(node => node.prop(key, value)); return this; },
            off(event) { nodes.forEach(node => node.off(event)); return this; },
            on(event, fn) { nodes.forEach(node => node.on(event, fn)); return this; }
        };
    }
    if (!connectionControls.has(selector)) { connectionControls.set(selector, new ConnectionControl()); }
    return connectionControls.get(selector);
}
vm.runInNewContext(visibleConnectionScript, {
    connectionsReady: false, fmtCount: String, connectionAddressCell() {},
    $: connectionControl, MihomoUI: UI, fmtBytes: UI.formatBytes,
    BootstrapDialog: {TYPE_WARNING: 'warning', confirm: options => confirmations.push(options)},
    ajaxCall: (url, data, done) => closeRequests.push({url, data, done}),
    overviewPoller: {refresh: () => overviewRefreshes++}, actionFailed: () => failures++
});
const connectionGridFixture6 = connectionControl('#grid-connections');
const visibleClose = connectionControl('#close-visible-connections');
const allClose = connectionControl('#close-all-connections');
function loadConnectionPage(ids) {
    connectionGridFixture6.handlers['load.rs.jquery.bootgrid']();
    assert.equal(visibleClose.disabled, true);
    pageButtons = ids.map(id => new ConnectionControl(id));
    connectionGridFixture6.handlers['loaded.rs.jquery.bootgrid']();
}
const clickVisible = () => visibleClose.handlers.click();
clickVisible();
assert.equal(confirmations.length, 0, 'No action before loading');
loadConnectionPage([]); clickVisible();
loadConnectionPage(['', ' \t ', '\0', '\0 \0', undefined, null]); clickVisible();
assert.equal(visibleClose.disabled, true);
assert.equal(confirmations.length, 0, 'Empty/invalid IDs must never invoke close-all');
loadConnectionPage(['one']); clickVisible();
assert.equal(allClose.disabled, true, 'Other close controls are disabled during confirmation');
confirmations.at(-1).callback(false);
assert.equal(closeRequests.length, 0, 'Cancellation sends no requests');
assert.equal(visibleClose.disabled, false);
assert.equal(allClose.disabled, false);

const targets = ['one', 'two', 'three', 'four', 'five'];
loadConnectionPage([...targets, 'one', '', '  ', undefined]);
clickVisible();
assert(confirmations.at(-1).message.includes('Close 5 connections'), 'Confirmation counts unique valid IDs');
clickVisible(); allClose.handlers.click(); pageButtons[0].handlers.click.call(pageButtons[0]);
assert.equal(confirmations.length, 2, 'Repeated clicks cannot open a second batch');
assert.equal(closeRequests.length, 0, 'No writes before confirmation, including other close controls');
// Search/page changes and new arrivals while the modal is open must not alter its snapshot.
loadConnectionPage(['other-page', 'new-arrival']);
assert.equal(visibleClose.disabled, true);
assert(pageButtons.every(button => button.disabled));
confirmations.at(-1).callback(true);
assert.equal(closeRequests.length, 3, 'Bounded concurrency starts three requests');
assert.equal(connectionControl('#close-visible-state').label, 'Close requests completed: 0/5; failed or unconfirmed: 0.');
closeRequests[1].done({status: 'failed'}, 'success'); // Already gone or controller failure.
assert.equal(closeRequests.length, 4, 'A failed request frees its slot');
closeRequests[0].done(null, 'error');
assert.equal(closeRequests.length, 5);
loadConnectionPage(['yet-another-page']);
assert.equal(visibleClose.disabled, true, 'Loaded events cannot re-enable an active batch');
closeRequests[2].done({status: 'ok'}, 'success');
closeRequests[3].done({status: 'ok'}, 'success');
assert.equal(reloads, 0, 'Do not reload for each result');
closeRequests[4].done({status: 'ok'}, 'success');
assert.deepEqual(closeRequests.map(request => request.data.id), targets,
    'Only the original visible page is closed, once per ID');
assert(closeRequests.every(request => request.url === '/api/mihomo/dashboard/close_connection' && request.data.id.trim() !== ''));
assert.equal(connectionControl('#close-visible-state').label, 'Close requests completed: 5/5; failed or unconfirmed: 2.');
assert.equal(reloads, 1); assert.equal(overviewRefreshes, 1);
assert.equal(visibleClose.disabled, true, 'Wait for the refreshed table before allowing another batch');
loadConnectionPage([]);
assert.equal(visibleClose.disabled, true);
loadConnectionPage(['remaining']);
assert.equal(visibleClose.disabled, false, 'Controls recover after partial failure');
pageButtons[0].handlers.click.call(pageButtons[0]);
assert.equal(closeRequests.at(-1).data.id, 'remaining', 'Existing single-close still works');
closeRequests.at(-1).done({status: 'ok'}, 'success');
loadConnectionPage(['remaining']);
allClose.handlers.click();
assert.equal(closeRequests.at(-1).data.id, '', 'Only explicit Close all uses the empty ID');
closeRequests.at(-1).done({status: 'failed'}, 'success');
assert.equal(failures, 1);
assert.equal(gridOptions.search, '/api/mihomo/dashboard/connections');
console.log('Close visible: page snapshot, confirmation/cancel, empty IDs, deduplication, bounded requests, partial failure and recovery passed');

// Run the actual manual batch action and existing bounded queue against the
// rendered cards. No selection/mode endpoint is allowed by this fixture.
const translateScript = script => script.replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g,
    (_, label) => JSON.stringify(label));
const allClickScript = indexView.match(/        \$\('#test-all-groups'\)\.on\('click',[\s\S]*?\n        \}\);/)[0];
const testNodesScript = indexView.match(/        function testNodes\(names(?:,[^)]*)?\) \{[\s\S]*?\n        \}/)[0];
const loadGroupsScript = indexView.match(/        function loadGroups\(done\) \{[\s\S]*?\n        \}/)[0];
const probes = [], groupReads = [];
Object.assign(groupContext, {$autoSwitch: {prop: () => false}, autoSwitchGeneration: 0, autoTestEnabled: false});
let batchRefreshes = 0;
groupContext.ajaxCall = (url, params, done) => {
    assert.equal(url, '/api/mihomo/dashboard/test_delay');
    probes.push({name: params.name, done});
};
groupContext.ajaxGet = (url, params, done) => {
    assert.equal(url, '/api/mihomo/dashboard/proxies');
    groupReads.push(done);
};
groupContext.groupsPoller = {refresh: () => { batchRefreshes++; }};
vm.runInContext(translateScript(testNodesScript + allClickScript + loadGroupsScript), groupContext);
assert.match(indexView, /<button[^>]*type="button"[^>]*id="test-all-groups"[^>]*disabled/,
    'Native keyboard-accessible control starts disabled before groups load');
for (const response of [{ready: false}, {ready: true, groups: []},
    {ready: true, groups: [{name: 'Empty', members: []}, {name: 'Missing members'}]}]) {
    pollGroups(response);
    assert.equal(testAllDisabled, true);
    testAllHandler();
    assert.equal(probes.length, 0);
}
orderBy('config');
const batchNames = [...names, '__proto__', 'literal &gt;'];
const batchResponse = {ready: true, groups: [
    {name: foldNames[1], members: batchNames.map(name => ({name: encode(name), selected: true}))},
    {name: 'Shared', members: [{name: encode(batchNames[0])}, {name: encode(batchNames[1])}]}
]};
const originalBatch = JSON.stringify(batchResponse);
pollGroups(batchResponse);
assert.equal(testAllDisabled, false);
assert.equal(probes.length, 0, 'Loading groups never starts a batch automatically');
assert.equal(groupList(foldNames[1]).getAttribute('hidden'), '', 'Collapsed groups participate');
testAllHandler();
assert.equal(probes.length, 3, 'At most three probes start concurrently');
assert.equal(testProgress, `Latency tests: 0/${batchNames.length} · Failed: 0`);
assert.equal(testAllDisabled, true);
assert.equal(testsDisabled, true);
testAllHandler();
vm.runInContext("testNodes(['overlapping single/group test']);", groupContext);
assert.equal(probes.length, 3, 'Repeat clicks and per-group tests cannot overlap the batch');
vm.runInContext('loadGroups(function () {});', groupContext);
assert.equal(groupReads.length, 0, 'Polling does not interrupt a running batch');
fold(foldNames[1]);
assert.equal(testAllDisabled, true, 'Redraws retain the disabled batch control');
assert.equal(testsDisabled, true);
probes[1].done(null, 'error');
assert.equal(probes.length, 4, 'A failure releases a queue slot');
probes[1].done({status: 'ok'}, 'success');
assert.equal(probes.length, 4, 'Repeated callbacks do not advance the queue');
probes[0].done({status: 'error'}, 'success');
probes[2].done({status: 'ok'}, 'success');
for (let i = 3; i < batchNames.length; i++) { probes[i].done({status: 'ok'}, 'success'); }
assert.deepEqual(probes.map(probe => probe.name), batchNames, 'Exact decoded names are deduplicated across cards');
assert.equal(testProgress, `Latency tests: ${batchNames.length}/${batchNames.length} · Failed: 2`);
assert.equal(batchRefreshes, 1, 'Refresh results once after all probes settle');
assert.equal(testAllDisabled, false);
assert.equal(testsDisabled, false);
assert.equal(JSON.stringify(batchResponse), originalBatch, 'Selections and API data remain unchanged');
vm.runInContext('loadGroups(function () {});', groupContext);
groupReads.pop()(null, 'error');
assert.equal(testAllDisabled, true, 'Failed reads disable batch probes of stale cards');
testAllHandler();
assert.equal(probes.length, batchNames.length);
vm.runInContext('loadGroups(function () {});', groupContext);
groupReads.pop()(batchResponse, 'success');
assert.equal(testAllDisabled, false, 'An unchanged successful recovery re-enables the action');
testAllHandler();
assert.equal(probes.length, batchNames.length + 3, 'Completed batches can be retried');
for (let i = batchNames.length; i < batchNames.length * 2; i++) { probes[i].done({status: 'ok'}, 'success'); }
assert.equal(testProgress, `Latency tests: ${batchNames.length}/${batchNames.length} · Failed: 0`, 'Retry resets aggregate progress');
assert.equal(batchRefreshes, 2);
console.log('Test all groups: manual-only, empty/unavailable states, collapsed/shared nodes, exact names, bounded concurrency, overlap prevention, progress, failures and recovery passed');

// Notes persist literal, exact names and plain text, not HTML or decoded entities.
let savedNotes = null, noteWrites = 0;
const noteStorage = {
    getItem(key) { assert.equal(key, 'mihomo.proxy-notes.v1'); return savedNotes; },
    setItem(key, value) { assert.equal(key, 'mihomo.proxy-notes.v1'); noteWrites++; savedNotes = value; }
};
const notes = new UI.ProxyNotes(() => noteStorage);
const noteNames = [...names, '__proto__', 'constructor', 'literal &gt;', 'Literal &gt;'];
const literalNote = '<img src=x onerror=alert(1)> &amp; 中文 📝';
for (const name of noteNames) {
    assert.equal(notes.get(name), '');
    assert.equal(notes.set(name, literalNote), 'saved');
}
let reloadedNotes = new UI.ProxyNotes(() => noteStorage);
assert(noteNames.every(name => reloadedNotes.get(name) === literalNote));
assert.equal(reloadedNotes.get('literal >'), '', 'Do not decode local names twice');
assert.equal(reloadedNotes.set('literal &gt;', ' edited '), 'saved');
assert.equal(reloadedNotes.get('literal &gt;'), 'edited');
assert.equal(reloadedNotes.get('Literal &gt;'), literalNote, 'Names are case-sensitive');
assert.equal(reloadedNotes.set('__proto__', '  '), 'saved');
assert.equal(new UI.ProxyNotes(() => noteStorage).get('__proto__'), '', 'Empty notes remove persisted entries');
assert.equal(reloadedNotes.set('boundary', '中'.repeat(160)), 'saved');
const beforeInvalid = noteWrites;
for (const value of ['x'.repeat(161), null, 42, {}]) {
    assert.equal(reloadedNotes.set('boundary', value), 'invalid');
}
assert.equal(noteWrites, beforeInvalid, 'Invalid edits must not overwrite storage');
assert.equal(reloadedNotes.get('boundary'), '中'.repeat(160));
for (const corrupt of ['{', 'null', '42', '{}', '[null,3,{},["wrong",4],[3,"wrong"],["long","' + 'x'.repeat(161) + '"],["valid","ok"]]']) {
    savedNotes = corrupt;
    const recovered = new UI.ProxyNotes(() => noteStorage);
    assert.equal(recovered.get('wrong'), '');
    assert.equal(recovered.get('long'), '');
    assert.equal(recovered.get('valid'), corrupt.includes('valid') ? 'ok' : '');
    assert.equal(recovered.set('new', 'note'), 'saved');
}
for (const unavailable of [
    () => { throw new Error('Storage blocked'); },
    () => ({getItem() { return null; }, setItem() { throw new Error('Quota exceeded'); }})
]) {
    const temporary = new UI.ProxyNotes(unavailable);
    assert.equal(temporary.set('temporary', 'note'), 'temporary');
    assert.equal(temporary.get('temporary'), 'note');
    assert.equal(temporary.set('temporary', ''), 'temporary');
    assert.equal(temporary.get('temporary'), '');
}
console.log('Proxy notes: persistence, exact names, Unicode, removal, length limits, corrupt and unavailable storage passed');

// Execute the actual editor handlers and render path; no network helpers exist.
const noteEditorScript = indexView.match(/        let noteName = null, noteFocusKey = null;[\s\S]*?        \$\('#proxy-note-cancel'\)\.on\('click', closeNoteEditor\);/)[0]
    .replace(/\{\{ lang\._\('([^']*)'\) \| json_encode \}\}/g, (_, label) => JSON.stringify(label));
vm.runInContext(noteEditorScript, groupContext);
assert(indexView.includes('id="proxy-note-editor" hidden'));
assert(indexView.includes('maxlength="160"'));
assert(indexView.includes('aria-describedby="proxy-note-help"'));
const noteResponse = {ready: true, groups: [
    {name: 'Notes A', members: [{name: encode(specialName), selected: true}, {name: 'Other'}]},
    {name: 'Notes B', members: [{name: encode(specialName)}]}
]};
const originalNoteResponse = JSON.stringify(noteResponse);
const noteButtons = () => pollingBox.querySelectorAll('button[data-name]').filter(node => node.attrs.class.includes('cmd-proxy-note'));
const noteTexts = () => pollingBox.querySelectorAll('small[data-proxy-note]');
function editNote(name, occurrence = 0) {
    const button = noteButtons().filter(node => node.attrs['data-name'] === name)[occurrence];
    assert.equal(button.attrs.type, 'button');
    assert.equal(button.attrs['aria-label'], 'Edit local note: ' + name);
    pollingDoc.activeElement = button;
    noteHandler.call(button);
    assert.equal(noteControl('#proxy-note-name').label, name);
    assert.equal(noteControl('#proxy-note-editor').hidden, false);
    assert.equal(pollingDoc.activeElement, noteControl('#proxy-note-text')[0]);
    return button.attrs['data-focus-key'];
}
function saveNote(value) {
    noteControl('#proxy-note-text').val(value);
    let prevented = false;
    noteControl('#proxy-note-editor').handlers.submit({preventDefault() { prevented = true; }});
    assert(prevented, 'Notes never submit a form to the server');
}
pollGroups(noteResponse);
assert.equal(noteTexts().length, 0);
const noteFocus = editNote(specialName);
noteControl('#proxy-note-text').val('unsaved draft');
noteResponse.groups[0].members[0].delay = 32;
pollGroups(noteResponse);
assert.equal(noteControl('#proxy-note-text').value, 'unsaved draft', 'Changed polls preserve drafts');
assert.equal(pollingDoc.activeElement, noteControl('#proxy-note-text')[0]);
const noteSelections = selectedNames(), noteOrder = displayedMembers();
const noteList = pollingBox.querySelectorAll('ul[data-group]')[0];
noteList.scrollTop = 67;
saveNote(literalNote);
assert.equal(noteControl('#proxy-note-editor').hidden, true);
assert.equal(noteControl('#proxy-note-state').label, 'Local note saved.');
assert.equal(pollingDoc.activeElement.attrs['data-focus-key'], noteFocus, 'Save returns focus to the edit control');
assert.equal(pollingBox.querySelectorAll('ul[data-group]')[0].scrollTop, 67);
assert.deepEqual(noteTexts().map(node => node.textContent), [literalNote, literalNote], 'Shared proxies show the same literal note');
assert.equal(new UI.ProxyNotes(() => groupContext.localStorage).get(specialName), literalNote);
assert.deepEqual(selectedNames(), noteSelections);
assert.deepEqual(displayedMembers(), noteOrder);
const notedRow = pollingBox.children[0];
pollGroups(noteResponse);
assert.equal(pollingBox.children[0], notedRow, 'Notes preserve the unchanged-poll optimization');
editNote(specialName, 1);
assert.equal(noteControl('#proxy-note-text').value, literalNote);
noteControl('#proxy-note-text').val('discard');
noteControl('#proxy-note-cancel').handlers.click();
assert.deepEqual(noteTexts().map(node => node.textContent), [literalNote, literalNote]);
assert.equal(noteControl('#proxy-note-editor').hidden, true);
editNote(specialName);
saveNote('x'.repeat(161));
assert.equal(noteControl('#proxy-note-editor').hidden, false);
assert(noteControl('#proxy-note-state').label.includes('160'));
assert.equal(noteControl('#proxy-note-text').value.length, 161, 'Invalid drafts remain editable');
assert.deepEqual(noteTexts().map(node => node.textContent), [literalNote, literalNote]);
groupContext.testing = true;
saveNote('changed');
assert.equal(testsDisabled, true, 'Saving during latency tests retains disabled probe controls');
groupContext.testing = false;
for (const unavailable of [{ready: false}, {ready: true, groups: []}]) {
    editNote(specialName);
    pollGroups(unavailable);
    saveNote('offline edit');
    assert.equal(pollingDoc.activeElement, pollingBox, 'Missing row returns focus to the groups container');
    pollGroups(noteResponse);
    assert.deepEqual(noteTexts().map(node => node.textContent), ['offline edit', 'offline edit']);
}
editNote(specialName);
saveNote('');
assert.equal(noteTexts().length, 0);
assert.equal(new UI.ProxyNotes(() => groupContext.localStorage).get(specialName), '');
// Failed persistence remains visible and honest, including failure to delete.
groupContext.localStorage.setItem = () => { throw new Error('Quota exceeded'); };
editNote(specialName);
saveNote('temporary');
assert(noteControl('#proxy-note-state').label.includes('only for this page visit'));
assert.deepEqual(noteTexts().map(node => node.textContent), ['temporary', 'temporary']);
editNote(specialName);
saveNote('');
assert.equal(noteTexts().length, 0);
assert(noteControl('#proxy-note-state').label.includes('only for this page visit'));
// Only the test's deliberate latency update changed its API fixture.
noteResponse.groups[0].members[0].delay = undefined;
assert.equal(JSON.stringify(noteResponse), originalNoteResponse);
console.log('Proxy note editor: shared rows, literal rendering, drafts across polls, save/cancel/remove, focus, recovery and no API calls passed');
