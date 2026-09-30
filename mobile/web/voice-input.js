// Use a fresh Web Speech instance for each physical hold. In particular, iOS
// home-screen web apps can silently stop returning results on a reused object.
(() => {
  let current = null;
  const endTimeout = 3000;

  function finish(session) {
    if (session.ended) return;
    session.ended = true;
    clearTimeout(session.startTimer);
    clearTimeout(session.endTimer);
    session.resolveEnd();
  }

  function accepts(session) {
    return current === session && !session.cancelled && !session.ended;
  }

  function abort(session) {
    session.cancelled = true;
    clearTimeout(session.startTimer);
    if (!session.ended) {
      session.endTimer ??= setTimeout(() => finish(session), endTimeout);
      try { session.recognizer.abort(); } catch { finish(session); }
    }
    return session.end;
  }

  window.sayFridgeVoiceInput = {
    start(onWords, onError, shouldContinue) {
      if (!shouldContinue()) return false;
      const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (!Recognition) { onError('not supported'); return false; }
      if (current && !current.ended) {
        // An earlier screen can be disposed before its abort/end completes.
        abort(current);
        onError('busy');
        return false;
      }
      const recognizer = new Recognition();
      const session = { recognizer, ended: false, cancelled: false };
      session.end = new Promise(resolve => { session.resolveEnd = resolve; });
      current = session;
      recognizer.lang = 'en-US';
      recognizer.interimResults = true;
      recognizer.continuous = true;
      recognizer.onstart = () => {
        clearTimeout(session.startTimer);
        if (session.ended) {
          // Permission can arrive even after our bounded cleanup completed.
          try { recognizer.abort(); } catch { /* Already disconnected. */ }
        } else if (session.cancelled || !shouldContinue()) abort(session);
      };
      recognizer.onresult = event => {
        if (!accepts(session)) return;
        const phrases = [];
        for (let i = 0; i < event.results.length; i++) {
          const result = event.results.item(i);
          phrases.push(result.item(0).transcript);
        }
        onWords(phrases.join(' ').trim());
      };
      recognizer.onerror = event => {
        if (!accepts(session)) return;
        // stop() may produce no-speech/aborted after the last partial result.
        if (session.stopping && ['aborted', 'no-speech'].includes(event.error)) return;
        abort(session);
        onError(event.error);
      };
      recognizer.onend = () => finish(session);
      session.startTimer = setTimeout(() => {
        if (!accepts(session)) return;
        abort(session);
        onError('start timeout');
      }, 10000);
      try {
        // Do not await permissions or another Future before this call: iOS
        // requires start() to retain the pointer-down's user activation.
        recognizer.start();
        return true;
      } catch (error) {
        finish(session);
        onError(error.name || 'start failed');
        return false;
      }
    },
    stop() {
      const session = current;
      if (!session || session.ended) return Promise.resolve();
      session.stopping = true;
      clearTimeout(session.startTimer);
      session.endTimer ??= setTimeout(() => {
        abort(session);
        finish(session);
      }, endTimeout);
      try { session.recognizer.stop(); } catch { abort(session); }
      return session.end;
    },
    cancel() {
      return current ? abort(current) : Promise.resolve();
    },
  };
})();
