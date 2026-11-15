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
const compactCSS = indexView.match(/<style>([\s\S]*?)<\/style>/)[1].replace(/\/\*[\s\S]*?\*\//g, '');
const selectors = Array.from(compactCSS.matchAll(/([^{}]+)\{/g), match => match[1].trim())
    .filter(selector => !selector.startsWith('@media'));
assert(selectors.length > 0);
assert(selectors.every(selector => selector.startsWith('#mihomo-overview.mihomo-compact ')));
assert.match(compactCSS, /#traffic-chart-container\s*\{ height: 140px !important;/);
assert.match(indexView, /id="traffic-chart-container" style="height: 200px;"/);
assert.match(compactCSS, /@media \(min-width: 1200px\)[\s\S]*width: 33\.333333%;/);
assert(!/display:\s*none|visibility:\s*hidden/.test(compactCSS), 'Compact mode must not hide controls or status');
console.log('Experimental compact overview: opt-in, persistence/removal, storage failures, chart resize and scoped styles passed');
