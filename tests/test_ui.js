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
const logView = fs.readFileSync(require('node:path').join(__dirname,
    '../src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/log.volt'), 'utf8');
const logScript = logView.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
vm.runInNewContext(logScript, {
    document: fakeDocument,
    $: selector => selector === fakeDocument ? {ready: fn => fn()} : control(selector),
    ajaxGet: (url, params, done) => requests.push({params, done}),
    setInterval: fn => { logTimer = fn; }, MihomoUI: {decodeApiText: value => { logDecodes++; return decode(value); }}
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
const render = () => UI.renderProxyGroups(groupBox, groups, {testGroup: 'Test group', testNode: 'Test node'}, value => value + ' ms', () => 'label-success');
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

// Run the dashboard render path with fresh API objects and the real DOM renderer.
// Unchanged polling must retain nodes, focus and scroll without allocating DOM.
const renderGroupsScript = indexView.match(/(?:        let renderedGroups = null;\n)?        function renderGroups\(data\) \{[\s\S]*?\n        \}/)[0]
    .replace(/\{\{[\s\S]*?\}\}/g, '"translated"');
let groupAllocations = 0;
const pollingDoc = {activeElement: null, createElement(tag) { groupAllocations++; return new DomNode(this, tag); }};
const pollingBox = pollingDoc.createElement('div');
const groupContext = vm.createContext({
    $: selector => {
        assert.equal(selector, '#proxy-groups');
        return {0: pollingBox, html: text => {
            const placeholder = pollingDoc.createElement('placeholder');
            placeholder.textContent = text;
            pollingBox.replaceChildren(placeholder);
        }};
    },
    MihomoUI: UI, delayText: value => value + ' ms', delayClass: () => 'label-success'
});
vm.runInContext(renderGroupsScript, groupContext);
const groupResponse = {ready: true, groups: [{name: 'Group', type: 'Selector', members: [
    {name: 'First', type: 'test', selected: true, delay: 20},
    {name: 'Second', type: 'test', selected: false, delay: 30}
]}]};
function pollGroups(response = groupResponse) {
    groupContext.response = JSON.parse(JSON.stringify(response));
    vm.runInContext('renderGroups(response);', groupContext);
}
pollGroups();
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
}
// Both placeholder states invalidate the snapshot, even when recovery returns
// exactly the same groups that were displayed before the interruption.
for (const placeholder of [{ready: false}, {ready: true, groups: []}]) {
    pollGroups(placeholder);
    assert.equal(pollingBox.children[0].tagName, 'placeholder');
    pollGroups();
    assert.equal(pollingBox.children[0].tagName, 'div', 'Recovery must replace the placeholder');
    const recoveredRow = pollingBox.children[0];
    pollGroups();
    assert.equal(pollingBox.children[0], recoveredRow);
}
console.log('Proxy polling skips unchanged DOM, preserves focus/scroll and renders changes/recovery: all checks passed');

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
    const document = {createElement: tag => new DomNode(document, tag), getElementById: id => item('#' + id)[0]};
    function item(selector) {
        if (typeof selector !== 'string') { return selector; }
        if (!items.has(selector)) {
            items.set(selector, {0: document.createElement('select'), value: '', label: '', handlers: {}, disabled: false,
                val(value) { if (value === undefined) { return this.value; } this.value = value; return this; },
                text(value) { this.label = value; return this; }, empty() { this.label = ''; return this; },
                prop(key, value) { this[key] = value; return this; },
                on(event, selector, fn) { this.handlers[fn ? selector : event] = fn || selector; return this; }});
        }
        return items.get(selector);
    }
    const page = {item, gets, posts, confirms, refreshes: 0, renders: 0, confirm: true};
    const context = vm.createContext({document, $: item, MihomoUI: UI,
        window: {get localStorage() { if (!storage) { throw new Error('denied'); } return storage; },
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
page.item('#proxy-groups').handlers['.cmd-select']();
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
