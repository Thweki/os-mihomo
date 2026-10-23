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
    return {formatBytes, TrafficHistory, theme, decodeApiText};
}));
