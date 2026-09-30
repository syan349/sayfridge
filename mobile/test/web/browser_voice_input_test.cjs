const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function fixture() {
  const instances = [];
  const timers = new Map();
  let timerId = 0;
  class Recognition {
    constructor() { instances.push(this); this.aborts = 0; this.starts = 0; }
    start() {
      assert.equal(++this.starts, 1, 'WebKit recognizers must not be reused');
    }
    abort() { this.aborts++; }
    stop() { this.stopped = true; }
    result(...phrases) {
      this.onresult({ results: { length: phrases.length,
        item: i => ({ item: () => ({ transcript: phrases[i] }) }) } });
    }
  }
  const window = { webkitSpeechRecognition: Recognition };
  vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../../web/voice-input.js'), 'utf8'), {
    window,
    setTimeout: (callback, delay) => { timers.set(++timerId, { callback, delay }); return timerId; },
    clearTimeout: id => timers.delete(id),
  });
  const words = [], errors = [];
  let holding = true;
  return { window, instances, timers, words, errors,
    start: () => window.sayFridgeVoiceInput.start(words.push.bind(words), errors.push.bind(errors), () => holding),
    release: () => { holding = false; },
  };
}

test('cancel then repeat uses a fresh recognizer and isolates late callbacks', async () => {
  const f = fixture();
  assert.equal(f.start(), true);
  const first = f.instances[0];
  first.onstart(); first.result('cancelled words');
  let ended = false;
  const cancelling = f.window.sayFridgeVoiceInput.cancel().then(() => { ended = true; });
  first.onerror({ error: 'aborted' }); first.result('discard this');
  await Promise.resolve();
  assert.equal(ended, false, 'abort returns before end');
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
  const timeout = [...f.timers.values()].find(timer => timer.delay === 3000);
  timeout.callback(); await cancelling;
  assert.equal(f.start(), true);
  const next = f.instances[1];
  first.onstart(); first.result('late permission transcript'); first.onerror({ error: 'aborted' });
  assert.equal(first.aborts, 2);
  assert.equal(next.aborts, 0);
  next.onstart(); next.result('new recording');
  assert.deepEqual(f.words, ['new recording']);
  assert.deepEqual(f.errors, []);
});

test('release before asynchronous onstart immediately aborts the microphone', () => {
  const f = fixture(); f.start(); f.release();
  const first = f.instances[0]; first.onstart(); first.result('discard');
  assert.equal(first.aborts, 1);
  assert.deepEqual(f.words, []);
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
