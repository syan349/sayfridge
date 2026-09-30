(() => {
  const voice = window.sayFridgeVoiceInput;
  const hold = document.getElementById('hold');
  const cancel = document.getElementById('cancel');
  const mic = document.getElementById('mic');
  const status = document.getElementById('status');
  const words = document.getElementById('words');
  const diagnostics = document.getElementById('diagnostics');
  let holding = false;
  let active = false;
  let generation = 0;
  let build = '本地检查或尚未提供版本信息';
  let microphone = '尚未检查';
  const report = () => JSON.stringify({ build, microphone,
    browser: window.sayFridgeBrowserDiagnostics(), voice: voice.diagnostics() }, null, 2);
  const refresh = () => { diagnostics.textContent = report(); };
  const tint = visible => window.sayFridgeSetVoiceOverlayVisible(visible);

  async function finish(discard) {
    holding = false;
    if (!active) return;
    active = false;
    if (discard) ++generation;
    hold.disabled = true;
    mic.disabled = true;
    cancel.disabled = true;
    status.textContent = discard ? '正在取消并释放麦克风…' : '正在结束录音…';
    await (discard ? voice.cancel() : voice.stop());
    tint(false);
    hold.disabled = false;
    mic.disabled = false;
    if (discard) words.textContent = '已取消本次文字';
    status.textContent = '麦克风已结束，可以再次按住说话';
    refresh();
  }

  hold.addEventListener('pointerdown', event => {
    if (active || hold.disabled) return;
    event.preventDefault();
    hold.setPointerCapture(event.pointerId);
    holding = active = true;
    const attempt = ++generation;
    words.textContent = '正在识别…';
    status.textContent = '正在监听';
    cancel.disabled = false;
    mic.disabled = true;
    tint(true);
    voice.start(text => {
      if (attempt === generation) words.textContent = text;
    }, error => {
      if (attempt !== generation) return;
      active = holding = false;
      cancel.disabled = true;
      mic.disabled = false;
      tint(false);
      status.textContent = '识别错误：' + error;
      refresh();
    }, () => holding && attempt === generation);
  });
  hold.addEventListener('pointerup', () => finish(false));
  hold.addEventListener('pointercancel', () => finish(true));
  document.addEventListener('visibilitychange', () => { if (document.hidden) finish(true); });
  cancel.addEventListener('click', () => finish(true));
  document.getElementById('clear').addEventListener('click', () => { words.textContent = '文字已清空'; });
  document.getElementById('tint').addEventListener('click', () => {
    tint(!document.documentElement.classList.contains('voice-overlay-visible'));
    refresh();
  });
  document.getElementById('copy').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(report()); status.textContent = '诊断信息已复制'; }
    catch { status.textContent = '无法自动复制，可长按选中下面的诊断信息'; }
  });
  mic.addEventListener('click', async () => {
    // Never open a second getUserMedia track while Web Speech is active on iOS.
    if (active) return;
    hold.disabled = mic.disabled = true;
    let stream, audio;
    try {
      await voice.cancel();
      status.textContent = '正在测试麦克风，请说一句话…';
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      audio = new (window.AudioContext || window.webkitAudioContext)();
      const analyser = audio.createAnalyser();
      analyser.fftSize = 256;
      const silence = audio.createGain();
      silence.gain.value = 0;
      audio.createMediaStreamSource(stream).connect(analyser);
      analyser.connect(silence); silence.connect(audio.destination);
      await audio.resume();
      const samples = new Uint8Array(analyser.fftSize);
      let peak = 0;
      for (let i = 0; i < 12; i++) {
        await new Promise(resolve => setTimeout(resolve, 100));
        analyser.getByteTimeDomainData(samples);
        const rms = Math.sqrt(samples.reduce((sum, value) => sum + ((value - 128) / 128) ** 2, 0) / samples.length);
        peak = Math.max(peak, rms);
      }
      const track = stream.getAudioTracks()[0];
      microphone = { muted: track.muted, state: track.readyState, maxRms: Number(peak.toFixed(5)) };
      status.textContent = peak > .005 ? '麦克风能收到声音，可以再测试语音识别' : '麦克风已打开，但未检测到声音；可再次测试并讲话';
    } catch (error) {
      microphone = { error: error.name };
      status.textContent = '麦克风测试失败：' + error.name;
    } finally {
      stream?.getTracks().forEach(track => track.stop());
      if (audio) await audio.close().catch(() => {});
      hold.disabled = mic.disabled = false;
      refresh();
    }
  });
  fetch('build-info.json', { cache: 'no-store' }).then(response => response.json())
    .then(value => { build = value; refresh(); }).catch(() => {});
  setInterval(refresh, 500);
  refresh();
})();
