const assert = require('node:assert/strict');
const {TrafficHistory, formatBytes} = require('../src/usr/local/www/js/mihomo/ui.js');
assert.equal(formatBytes(738, 'en-US'), '738.0 B');
assert.equal(formatBytes(1536, 'en-US'), '1.5 KiB');
assert.equal(formatBytes(1536, 'de-DE'), '1,5 KiB');
assert.equal(formatBytes(null), '0.0 B');
assert.equal(formatBytes(NaN), '—');
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
            prop(key) { return this[key]; }, on(event, fn) { this.handlers[event] = fn; return this; },
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
vm.runInNewContext(logScript, {
    document: fakeDocument,
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
const names = ['name" data-unexpected="value', "single' quote", '<tag>&value', '001', '中文\\name'];
const encode = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const groups = names.map(name => ({name: encode(name), type: 'Selector', members: [{name: encode(name), type: 'test', selected: true, delay: 20}]}));
const render = () => UI.renderProxyGroups(groupBox, groups, {testGroup: 'Test group', testNode: 'Test node', memberCount: 'Members: %s'}, value => value + ' ms', () => 'label-success');
render();
const lists = groupBox.querySelectorAll('ul[data-group]');
assert.deepEqual(lists.map(node => node.getAttribute('data-group')), names);
const members = groupBox.querySelectorAll('li[data-member]');
assert.deepEqual(members.map(node => node.getAttribute('data-member')), names);
assert(members.every(node => !Object.hasOwn(node.attrs, 'data-unexpected')));
const buttons = groupBox.querySelectorAll('button[data-focus-key]');
assert.equal(buttons.length, names.length * 3);
assert(buttons.every(node => node.attrs.type === 'button'), 'Selection has native keyboard activation');
assert.equal(buttons[1].attrs['aria-pressed'], 'true');
assert.equal(buttons[2].attrs['aria-label'], 'Test node: ' + names[0]);
assert.equal(buttons[1].children[1].textContent, ' ' + names[0] + ' ');
lists[0].scrollTop = 172;
doc.activeElement = buttons[1];
render();
assert.equal(groupBox.querySelectorAll('ul[data-group]')[0].scrollTop, 172);
assert.notEqual(doc.activeElement, buttons[1], 'Refresh replaces nodes');
assert.equal(doc.activeElement.attrs['data-focus-key'], buttons[1].attrs['data-focus-key'], 'Refresh restores keyboard focus by exact name');
assert(groupBox.contains(doc.activeElement));

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
    setTimeout: fn => modeTimeouts.push(fn), actionFailed: () => { modeFailures++; }
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
let favoriteNotice = '', testsDisabled = false, favoriteHandler, collapseHandler, testGroupHandler;
const dashboardStorage = new Map();
const dashboardFavorites = new UI.ProxyFavorites(() => ({
    getItem: key => dashboardStorage.get(key) || null,
    setItem: (key, value) => dashboardStorage.set(key, value)
}));
const groupContext = vm.createContext({
    $: selector => {
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
    MihomoUI: UI, favorites: dashboardFavorites, latestGroups: null, testing: false,
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
