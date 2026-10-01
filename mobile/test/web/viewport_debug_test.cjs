const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.resolve(__dirname, '../../web/viewport-debug.js'), 'utf8');
const debugManifest = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, '../../web/viewport-debug-manifest.json'), 'utf8',
));

function fixture() {
  const frames = [];
  const events = new Map();
  const viewportEvents = new Map();
  const elements = [];
  const manifest = { href: 'manifest.json' };
  const title = { content: 'SayFridge' };
  const rect = { top: 0, left: 0, width: 402, height: 812, bottom: 812 };
  const privateValue = 'private-password-inventory-and-token';
  const body = { getBoundingClientRect: () => rect, append: () => {} };
  const view = { getBoundingClientRect: () => rect };
  const document = {
    baseURI: 'https://example.test/', body, hidden: false,
    documentElement: { classList: { contains: () => false } },
    activeElement: { tagName: 'INPUT', value: privateValue },
    createElement: tag => {
      const element = { tag, style: {}, children: [], events: new Map(),
        append(...children) { this.children.push(...children); },
        addEventListener(type, callback) { this.events.set(type, callback); },
      };
      elements.push(element);
      return element;
    },
    querySelector: selector => selector.includes('manifest') ? manifest
      : selector.includes('apple-mobile') ? title
        : selector.includes('canvas') ? null : view,
    addEventListener: (type, callback) => events.set(type, callback),
  };
  let copied = null;
  const window = {
    devicePixelRatio: 3, innerWidth: 402, scrollY: 0,
    sayFridgeBrowserDiagnostics: () => ({
      standalone: true, statusBarStyle: 'default', innerHeight: rect.height,
      documentHeight: rect.height, visualViewportHeight: rect.height,
      screenHeight: 874, safeArea: [0, 0, 34, 0],
    }),
    requestAnimationFrame: callback => frames.push(callback),
    addEventListener: (type, callback) => events.set(type, callback),
    visualViewport: { width: 402, scale: 1,
      addEventListener: (type, callback) => viewportEvents.set(type, callback),
    },
  };
  vm.runInNewContext(source, {
    window, document, URLSearchParams, URL,
    location: { search: '?viewport-debug=1&secret=' + privateValue, origin: 'https://example.test/' },
    performance: { now: () => 10 },
    screen: { width: 402, availHeight: 874 },
    navigator: { maxTouchPoints: 5, clipboard: { writeText: async text => { copied = text; } } },
    // A report must not expose arbitrary fields even from the build-info endpoint.
    fetch: async (url, options) => {
      assert.equal(url.href, 'https://example.test/build-info.json');
      assert.equal(options.cache, 'no-store');
      return { ok: true, json: async () => ({ commit: 'abc123', built_at: '2026-10-01', secret: privateValue }) };
    },
  });
  const output = elements.find(element => element.tag === 'pre');
  const copy = elements.find(element => element.tag === 'button');
  return { rect, manifest, title, events, viewportEvents, privateValue, copy,
    flush: () => { while (frames.length) frames.shift()(); },
    report: () => JSON.parse(output.textContent), copied: () => copied,
  };
}

test('normal launches and invalid flags perform no DOM, storage or network work', () => {
  for (const search of ['', '?viewport-debug=0', '?viewport-debug=true']) {
    // No DOM, network or storage globals are available; touching them must fail.
    vm.runInNewContext(source, { location: { search }, URLSearchParams });
  }
});

test('Home Screen check keeps its opt-in at launch and retains raw viewport differences', () => {
  const f = fixture();
  assert.equal(f.manifest.href, 'viewport-debug-manifest.json');
  const start = new URL(debugManifest.start_url, 'https://example.test/');
  assert.equal(start.searchParams.get('viewport-debug'), '1');
  assert.equal(debugManifest.display, 'standalone');
  const reading = f.report().samples[0];
  assert.equal(reading.browser.screenHeight, 874);
  assert.equal(reading.browser.documentHeight, 812);
  assert.equal(reading.flutterView.height, 812);
  assert.deepEqual(reading.browser.safeArea, [0, 0, 34, 0]);
});

test('copy refreshes keyboard dimensions and excludes URL queries and input values', async () => {
  const f = fixture();
  // Allow the asynchronous, read-only build-info request to complete.
  await new Promise(resolve => setImmediate(resolve));
  f.rect.height = f.rect.bottom = 480;
  f.viewportEvents.get('resize')();
  f.events.get('resize')();
  f.flush();
  await f.copy.events.get('click')();
  const text = f.copied();
  const report = JSON.parse(text);
  assert.deepEqual(report.build, { commit: 'abc123', built_at: '2026-10-01' });
  assert.equal(report.samples[0].browser.documentHeight, 812);
  assert.equal(report.samples.at(-1).browser.documentHeight, 480);
  assert.equal(report.samples.at(-1).focusedElement, 'INPUT');
  assert.equal(text.includes(f.privateValue), false);
});

test('repeated resizes retain the cold-start reading and a bounded recent history', () => {
  const f = fixture();
  for (let i = 0; i < 30; i++) {
    f.rect.height = f.rect.bottom = 500 + i;
    f.events.get('resize')();
    f.flush();
  }
  const samples = f.report().samples;
  assert.equal(samples.length, 12);
  assert.equal(samples[0].event, 'startup');
  assert.equal(samples[0].browser.documentHeight, 812);
  assert.equal(samples.at(-1).browser.documentHeight, 529);
});
