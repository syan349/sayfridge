// Keep each hold separate. On iOS, gracefully stop even a cancelled hold:
// abort() can leave WebKit's audio session unusable on the following attempt.
(() => {
  let current = null;
  let sequence = 0;
  const history = [];
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const endTimeout = 3000;
  const releaseDelay = ios ? 350 : 0;

  function record(session, event, detail) {
    history.push({ session: session.id, event, detail, at: Date.now() });
    if (history.length > 64) history.shift();
  }

  function clearTimers(session) {
    for (const key of ['startTimer', 'audioTimer', 'resultTimer', 'endTimer']) {
      clearTimeout(session[key]);
    }
  }

  function finish(session) {
    if (session.ended) return;
    session.ended = true;
    clearTimers(session);
    record(session, 'end');
    // Speech end and microphone end are distinct events. If iOS reports speech
    // end first, wait for audio-end (bounded) before starting the settle delay.
    const settle = () => {
      clearTimeout(session.audioReleaseTimer);
      session.audioRelease = null;
      const release = () => {
        session.released = true;
        record(session, 'released');
        session.resolveEnd();
      };
      if (releaseDelay) setTimeout(release, releaseDelay);
      else release();
    };
    if (ios && session.audioStarted && !session.audioEnded) {
      session.audioRelease = settle;
      session.audioReleaseTimer = setTimeout(() => {
        record(session, 'audio-end-timeout');
        settle();
      }, 1000);
    } else settle();
  }

  function accepts(session) {
    return current === session && !session.cancelled && !session.ended;
  }

  function requestStop(session) {
    if (session.ended) return session.end;
    session.stopping = true;
    clearTimers(session);
    session.endTimer = setTimeout(() => {
      // abort is a last resort when the engine refuses a normal stop.
      record(session, 'stop-timeout');
      try { session.recognizer.abort(); } catch { /* Already disconnected. */ }
      finish(session);
    }, endTimeout);
    try { session.recognizer.stop(); } catch { finish(session); }
    return session.end;
  }

  function fail(session, code) {
    if (!accepts(session)) return;
    record(session, 'error', code);
    session.cancelled = true;
    requestStop(session);
    session.onError(code);
  }

  function waitForResult(session) {
    if (session.hasWords || session.resultTimer || !accepts(session)) return;
    session.resultTimer = setTimeout(() => fail(session, 'result timeout'), 15000);
  }

  window.sayFridgeVoiceInput = {
    start(onWords, onError, shouldContinue) {
      if (!shouldContinue()) return false;
      const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (!Recognition) { onError('not supported'); return false; }
      if (current && !current.released) {
        current.cancelled = true;
        requestStop(current);
        onError('busy');
        return false;
      }
      const recognizer = new Recognition();
      const session = {
        id: ++sequence, recognizer, onError,
        ended: false, released: false, cancelled: false, hasWords: false,
      };
      session.end = new Promise(resolve => { session.resolveEnd = resolve; });
      current = session;
      recognizer.lang = 'en-US';
      recognizer.interimResults = true;
      // iOS has one speech/audio task underneath Web Speech. End a completed
      // utterance normally instead of leaving a continuous task open.
      recognizer.continuous = !ios;
      recognizer.maxAlternatives = 1;
      recognizer.onstart = () => {
        record(session, 'listening');
        if (session.ended) {
          try { recognizer.abort(); } catch { /* Late permission after timeout. */ }
          return;
        }
        if (!session.stopping && !shouldContinue()) session.cancelled = true;
        if (session.stopping || session.cancelled) {
          requestStop(session);
          return;
        }
        clearTimeout(session.startTimer);
        if (!session.audioStarted && !session.hasWords) {
          session.audioTimer = setTimeout(() => fail(session, 'audio timeout'), 5000);
        }
        waitForResult(session);
      };
      recognizer.onaudiostart = () => {
        record(session, 'audio-start');
        session.audioStarted = true;
        clearTimeout(session.audioTimer);
        if (session.stopping || session.cancelled) requestStop(session);
        else waitForResult(session);
      };
      recognizer.onaudioend = () => {
        session.audioEnded = true;
        record(session, 'audio-end');
        session.audioRelease?.();
      };
      recognizer.onresult = event => {
        if (!accepts(session)) return;
        const phrases = [];
        for (let i = 0; i < event.results.length; i++) {
          const result = event.results.item(i);
          phrases.push(result.item(0).transcript);
        }
        const words = phrases.join(' ').trim();
        session.hasWords = words.length > 0;
        if (session.hasWords) {
          clearTimeout(session.audioTimer);
          clearTimeout(session.resultTimer);
          clearTimeout(session.startTimer);
        }
        record(session, 'result'); // Never store recognized words in diagnostics.
        onWords(words);
      };
      recognizer.onerror = event => {
        if (!accepts(session)) return;
        if (session.stopping && ['aborted', 'no-speech'].includes(event.error)) return;
        fail(session, event.error);
      };
      recognizer.onend = () => {
        if (accepts(session) && !session.stopping && !session.hasWords) {
          session.onError('no-speech');
        }
        finish(session);
      };
      session.startTimer = setTimeout(() => fail(session, 'start timeout'), 10000);
      record(session, 'start', ios ? 'single-utterance' : 'continuous');
      try {
        // Keep start() in the original physical pointer-down event.
        recognizer.start();
        return true;
      } catch (error) {
        finish(session);
        onError(error.name || 'start failed');
        return false;
      }
    },
    stop() {
      return current ? requestStop(current) : Promise.resolve();
    },
    cancel() {
      if (!current) return Promise.resolve();
      current.cancelled = true; // Discard words while stop releases the mic.
      record(current, 'cancel');
      return requestStop(current);
    },
    diagnostics() {
      return {
        revision: 'voice-stop-v2', ios,
        state: current ? {
          session: current.id, ended: current.ended, released: current.released,
          cancelled: current.cancelled, audioStarted: !!current.audioStarted,
          audioEnded: !!current.audioEnded,
          hasWords: current.hasWords,
        } : null,
        events: history.slice(),
      };
    },
  };
})();
