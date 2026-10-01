(() => {
  if (new URLSearchParams(location.search).get('viewport-debug') !== '1') return;

  // Keep the opt-in on Home Screen launch: the normal manifest starts at './'.
  document.querySelector('link[rel="manifest"]').href = 'viewport-debug-manifest.json';
  document.querySelector('meta[name="apple-mobile-web-app-title"]').content = 'SayFridge Check';

  const panel = document.createElement('details');
  panel.id = 'viewport-debug-panel';
  panel.open = true;
  panel.style.cssText = 'position:fixed;top:calc(env(safe-area-inset-top,0px) + 8px);'
    + 'left:8px;right:8px;max-width:460px;max-height:45dvh;overflow:auto;'
    + 'z-index:2147483646;background:#fff;color:#111;padding:12px;border:1px solid #4a672d;'
    + 'border-radius:12px;font:12px/1.4 monospace;box-sizing:border-box;';
  const summary = document.createElement('summary');
  summary.textContent = '视口检查（点击收起）';
  const note = document.createElement('p');
  note.textContent = '只读取屏幕尺寸和部署版本。先复制信息，再收起面板观察底部；信息不会上传。';
  const copy = document.createElement('button');
  copy.type = 'button';
  copy.textContent = '复制诊断信息';
  const output = document.createElement('pre');
  output.style.cssText = 'white-space:pre-wrap;overflow-wrap:anywhere;user-select:text;';
  panel.append(summary, note, copy, output);
  document.body.append(panel);

  let build = null;
  const samples = [];
  let framePending = false;
  const bounds = element => {
    if (!element) return null;
    const rect = element.getBoundingClientRect();
    return { top: rect.top, left: rect.left, width: rect.width, height: rect.height, bottom: rect.bottom };
  };
  const report = () => ({ revision: 'viewport-check-v1', origin: location.origin, build, samples });
  const render = () => { output.textContent = JSON.stringify(report(), null, 2); };
  const capture = event => {
    samples.push({
      event,
      elapsedMs: Math.round(performance.now()),
      browser: window.sayFridgeBrowserDiagnostics(),
      screenWidth: screen.width,
      screenAvailableHeight: screen.availHeight,
      devicePixelRatio: window.devicePixelRatio,
      maxTouchPoints: navigator.maxTouchPoints,
      innerWidth: window.innerWidth,
      scrollY: window.scrollY,
      visualViewportWidth: window.visualViewport?.width,
      visualViewportScale: window.visualViewport?.scale,
      desktopPreview: document.documentElement.classList.contains('desktop-preview'),
      body: bounds(document.body),
      flutterView: bounds(document.querySelector('flutter-view, flt-glass-pane')),
      canvas: bounds(document.querySelector('flutter-view canvas, flt-glass-pane canvas')),
      focusedElement: document.activeElement?.tagName,
    });
    // Preserve the cold-start reading as well as recent resize/keyboard events.
    if (samples.length > 12) samples.splice(1, samples.length - 12);
    render();
  };
  const schedule = event => {
    if (framePending) return;
    framePending = true;
    window.requestAnimationFrame(() => {
      framePending = false;
      capture(event);
    });
  };
  window.addEventListener('flutter-first-frame', () => schedule('flutter-first-frame'));
  window.addEventListener('resize', () => schedule('window-resize'));
  window.addEventListener('pageshow', () => schedule('pageshow'));
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) schedule('foreground');
  });
  window.visualViewport?.addEventListener('resize', () => schedule('visual-viewport-resize'));
  window.visualViewport?.addEventListener('scroll', () => schedule('visual-viewport-scroll'));
  copy.addEventListener('click', async () => {
    capture('copy');
    try {
      await navigator.clipboard.writeText(JSON.stringify(report(), null, 2));
      copy.textContent = '已复制';
    } catch {
      copy.textContent = '请长按选中下面的信息复制';
    }
  });
  capture('startup');
  fetch(new URL('build-info.json', document.baseURI), { cache: 'no-store' })
    .then(response => {
      if (!response.ok) throw new Error('Build info unavailable');
      return response.json();
    })
    .then(info => { build = { commit: info.commit, built_at: info.built_at }; render(); })
    .catch(() => { build = { unavailable: true }; render(); });
})();
