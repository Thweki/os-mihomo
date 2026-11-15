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
function control(selector) {
    if (!controls.has(selector)) {
        const item = {value: '', checked: false, label: '', handlers: {}, top: 100,
            0: {scrollHeight: 100}, val(value) { if (value === undefined) { return this.value; } this.value = value; return this; },
            text(value) { this.label = value; return this; },
            prop(key) { return this[key]; }, on(event, fn) { this.handlers[event] = fn; return this; },
            change(fn) { return this.on('change', fn); }, click(fn) { return this.on('click', fn); },
            scrollTop(value) { if (value === undefined) { return this.top; } this.top = value; return this; },
            outerHeight() { return 50; }};
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
    setInterval: () => {}, MihomoUI: {decodeApiText: decode}
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
let versionValue = 'original-version';
const writeRequests = [], messages = [];
const settingsContext = {
    $: selector => ({prop: () => {}, val: value => { versionValue = value; }}),
    syncManagedHidden: () => {}, getFormData: () => ({version: versionValue, mihomo: {enabled: '0'}}),
    ajaxCall: (url, data, done) => writeRequests.push({url, data, done}),
    handleFormValidation: () => {}, showResult: (...args) => messages.push(args),
    MihomoUI: UI, BootstrapDialog: {TYPE_DANGER: 'danger', TYPE_SUCCESS: 'success'},
    formChanges: () => [], reloadForm: () => {}, loadRawConfig: () => {}
};
vm.runInNewContext(applyFunction + '\napplySettings();', settingsContext);
assert.equal(writeRequests[0].data.version, 'original-version');
writeRequests[0].done({status: 'failed', message: 'Configuration changed. Reload before saving.'}, 'success');
assert.equal(writeRequests.length, 1, 'A stale model cannot reach apply');
assert.equal(messages.at(-1)[2], 'danger');
vm.runInNewContext('applySettings();', settingsContext);
writeRequests[1].done({result: 'saved', version: 'after-model-save'}, 'success');
assert.equal(writeRequests[2].url, '/api/mihomo/settings/apply');
assert.equal(writeRequests[2].data.version, 'after-model-save');
writeRequests[2].done({status: 'partial', message: 'Cron failed after configuration was saved.'});
assert.equal(messages.at(-1)[2], 'danger', 'Partial completion is not reported as success');
assert.equal(versionValue, 'after-model-save');

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
