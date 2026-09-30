const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function fixture({ ios = false } = {}) {
  const instances = [];
  const timers = new Map();
  let timerId = 0;
  class Recognition {
    constructor() { instances.push(this); this.aborts = 0; this.starts = 0; this.stops = 0; }
    start() {
      assert.equal(++this.starts, 1, 'WebKit recognizers must not be reused');
    }
    abort() { this.aborts++; }
    stop() { this.stops++; }
    result(...phrases) {
      this.onresult({ results: { length: phrases.length,
        item: i => ({ item: () => ({ transcript: phrases[i] }) }) } });
    }
  }
  const window = { webkitSpeechRecognition: Recognition };
  vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../../web/voice-input.js'), 'utf8'), {
    window,
    navigator: { userAgent: ios ? 'iPhone OS 27_0' : 'Chrome', platform: '', maxTouchPoints: 0 },
    setTimeout: (callback, delay) => { timers.set(++timerId, { callback, delay }); return timerId; },
    clearTimeout: id => timers.delete(id),
  });
  const words = [], errors = [];
  let holding = true;
  return { window, instances, timers, words, errors,
    start: () => { holding = true; return window.sayFridgeVoiceInput.start(words.push.bind(words), errors.push.bind(errors), () => holding); },
    release: () => { holding = false; },
    fire: delay => {
      const entry = [...timers.entries()].find(([, timer]) => timer.delay === delay);
      assert(entry, `Missing ${delay}ms timer`);
      timers.delete(entry[0]); entry[1].callback();
    },
  };
}

test('cancel stops gracefully then repeat uses a fresh recognizer and isolates late callbacks', async () => {
  const f = fixture();
  assert.equal(f.start(), true);
  const first = f.instances[0];
  first.onstart(); first.result('cancelled words');
  let ended = false;
  const cancelling = f.window.sayFridgeVoiceInput.cancel().then(() => { ended = true; });
  assert.equal(first.stops, 1);
  assert.equal(first.aborts, 0, 'cancellation must not poison the native audio session');
  first.onerror({ error: 'aborted' }); first.result('discard this');
  await Promise.resolve();
  assert.equal(ended, false, 'stop returns before end');
  first.onend(); await cancelling;
  assert.equal(f.start(), true);
  const next = f.instances[1];
  assert.notEqual(first, next);
  assert.equal(next.lang, 'en-US');
  assert.equal(next.interimResults, true);
  first.result('old result'); first.onerror({ error: 'network' }); first.onend();
  next.onstart(); next.result('two', 'tomatoes');
  const stopping = f.window.sayFridgeVoiceInput.stop();
  next.result('two tomatoes in my fridge'); next.onend(); await stopping;
  assert.deepEqual(f.words, ['cancelled words', 'two tomatoes', 'two tomatoes in my fridge']);
  assert.deepEqual(f.errors, []);
});

test('cancel timeout allows a fresh hold and aborts late permission on the old one', async () => {
  const f = fixture(); f.start();
  const first = f.instances[0];
  const cancelling = f.window.sayFridgeVoiceInput.cancel();
  f.fire(3000); await cancelling;
  assert.equal(f.start(), true);
  const next = f.instances[1];
  first.onstart(); first.result('late permission transcript'); first.onerror({ error: 'aborted' });
  assert.equal(first.aborts, 2);
  assert.equal(next.aborts, 0);
  next.onstart(); next.result('new recording');
  assert.deepEqual(f.words, ['new recording']);
  assert.deepEqual(f.errors, []);
});

test('release before asynchronous onstart stops the microphone and ignores late words', () => {
  const f = fixture(); f.start(); f.release();
  const first = f.instances[0]; first.onstart(); first.result('discard');
  assert.equal(first.stops, 1);
  assert.equal(first.aborts, 0);
  assert.deepEqual(f.words, []);
});

test('iOS uses single utterances and waits after end before allowing another hold', async () => {
  const f = fixture({ ios: true }); f.start();
  const first = f.instances[0]; first.onstart(); first.onaudiostart();
  assert.equal(first.continuous, false);
  let released = false;
  const cancelling = f.window.sayFridgeVoiceInput.cancel().then(() => { released = true; });
  first.onaudioend(); first.onend(); await Promise.resolve();
  assert.equal(released, false);
  assert.equal(f.start(), false, 'do not overlap audio session teardown');
  assert.equal(f.instances.length, 1);
  f.fire(350); await cancelling;
  assert.equal(f.start(), true);
  const next = f.instances[1]; next.onstart(); next.onaudiostart(); next.result('two potatoes');
  assert.deepEqual(f.words, ['two potatoes']);
  assert.deepEqual(f.errors, ['busy']);
});

test('iOS speech end waits for late microphone end and then settles', async () => {
  const f = fixture({ ios: true }); f.start();
  const first = f.instances[0]; first.onstart(); first.onaudiostart();
  let released = false;
  const cancelling = f.window.sayFridgeVoiceInput.cancel().then(() => { released = true; });
  first.onend(); await Promise.resolve();
  assert.equal(released, false);
  assert.equal([...f.timers.values()].some(timer => timer.delay === 350), false);
  first.onaudioend(); f.fire(350); await cancelling;
  assert.equal(released, true);
  assert.equal(first.aborts, 0);
});

test('missing microphone end has bounded cleanup rather than a permanently disabled button', async () => {
  const f = fixture({ ios: true }); f.start();
  const first = f.instances[0]; first.onstart(); first.onaudiostart();
  const cancelling = f.window.sayFridgeVoiceInput.cancel();
  first.onend(); f.fire(1000); f.fire(350); await cancelling;
  assert.equal(f.start(), true);
});

test('a recognizer that starts without capturing audio fails instead of listening forever', () => {
  const f = fixture({ ios: true }); f.start();
  const first = f.instances[0]; first.onstart(); f.fire(5000);
  assert.deepEqual(f.errors, ['audio timeout']);
  assert.equal(first.stops, 1);
  assert.equal(first.aborts, 0);
  first.result('late result');
  assert.deepEqual(f.words, []);
});

test('capturing audio without delivering results reports a silent recognition failure', () => {
  const f = fixture({ ios: true }); f.start();
  const first = f.instances[0]; first.onstart(); first.onaudiostart(); f.fire(15000);
  assert.deepEqual(f.errors, ['result timeout']);
  assert.equal(first.stops, 1);
  assert.equal([...f.timers.values()].some(timer => timer.delay === 5000), false);
});

test('result clears startup watchdogs even when the browser omits audio-start', () => {
  const f = fixture({ ios: true }); f.start();
  const first = f.instances[0]; first.onstart(); first.result('one bottle of milk');
  assert.equal(f.timers.size, 0);
  assert.deepEqual(f.errors, []);
});

test('release while permission is pending keeps a final stop result without cancelling it', async () => {
  const f = fixture(); f.start(); f.release();
  const first = f.instances[0];
  const stopping = f.window.sayFridgeVoiceInput.stop();
  first.onstart(); first.result('final words'); first.onend(); await stopping;
  assert.equal(first.aborts, 0);
  assert.deepEqual(f.words, ['final words']);
});

test('spontaneous empty recognition end does not leave a misleading listening state', () => {
  const f = fixture({ ios: true }); f.start();
  const first = f.instances[0]; first.onstart(); first.onend();
  assert.deepEqual(f.errors, ['no-speech']);
});

test('diagnostics are bounded and do not contain recognized text', async () => {
  const f = fixture();
  for (let i = 0; i < 30; i++) {
    f.start(); const recognizer = f.instances.at(-1);
    recognizer.onstart(); recognizer.onaudiostart(); recognizer.result('private phrase');
    const stopping = f.window.sayFridgeVoiceInput.stop(); recognizer.onend(); await stopping;
  }
  const report = f.window.sayFridgeVoiceInput.diagnostics();
  assert.equal(report.events.length, 64);
  assert.equal(JSON.stringify(report).includes('private phrase'), false);
  assert.equal(report.state.released, true);
});

test('errors release the recognizer and a subsequent hold receives results', async () => {
  const f = fixture(); f.start();
  const first = f.instances[0]; first.onstart(); first.onerror({ error: 'network' });
  const cancelling = f.window.sayFridgeVoiceInput.cancel(); first.onend(); await cancelling;
  f.start(); const next = f.instances[1]; next.onstart(); next.result('try again');
  assert.deepEqual(f.words, ['try again']);
  assert.deepEqual(f.errors, ['network']);
});

test('stop retains the last partial result when the browser ends with no-speech', async () => {
  const f = fixture(); f.start(); const first = f.instances[0];
  first.onstart(); first.result('one bottle of milk');
  const stopping = f.window.sayFridgeVoiceInput.stop();
  first.onerror({ error: 'no-speech' }); first.onend(); await stopping;
  assert.deepEqual(f.words, ['one bottle of milk']);
  assert.deepEqual(f.errors, []);
});
