(() => {
  // Keep Flutter's full-page viewport/keyboard behavior on touch devices. Desktop
  // browsers render into a resizable host, so every route stays inside the frame.
  const desktopBrowser = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  window.sayFridgeIsDesktopBrowser = desktopBrowser;
  if (desktopBrowser) {
    document.documentElement.classList.add('desktop-preview');
  }

  // Flutter Web reports no device safe-area padding. Read CSS insets so the
  // app's SafeArea widgets protect controls while backgrounds fill the screen.
  const safeAreaProbe = document.createElement('div');
  safeAreaProbe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;'
    + 'padding:env(safe-area-inset-top, 0px) env(safe-area-inset-right, 0px) '
    + 'env(safe-area-inset-bottom, 0px) env(safe-area-inset-left, 0px);';
  document.body.appendChild(safeAreaProbe);
  window.sayFridgeReadSafeArea = () => {
    if (desktopBrowser) return [0, 0, 0, 0];
    const style = getComputedStyle(safeAreaProbe);
    return [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft]
      .map(value => parseFloat(value) || 0);
  };

  // Recreate the fixed top surface when its color changes. Some iOS versions
  // sample a composited surface once and ignore later background-only changes.
  const themeColor = document.querySelector('meta[name="theme-color"]');
  const normalThemeColor = themeColor?.getAttribute('content');
  const normalHtmlBackground = document.documentElement.style.backgroundColor;
  const normalBodyBackground = document.body.style.backgroundColor;
  window.sayFridgeSetVoiceOverlayVisible = visible => {
    document.documentElement.classList.toggle('voice-overlay-visible', visible);
    const color = visible ? '#73766f' : '#f7fded';
    if (!desktopBrowser) {
      document.documentElement.style.backgroundColor = visible ? '#73766f' : normalHtmlBackground;
      document.body.style.backgroundColor = visible ? '#73766f' : normalBodyBackground;
      const surface = document.getElementById('status-bar-surface');
      if (surface) {
        const replacement = surface.cloneNode(false);
        replacement.style.backgroundColor = color;
        surface.replaceWith(replacement);
      }
    }
    if (themeColor) {
      if (visible) themeColor.setAttribute('content', '#73766f');
      else if (normalThemeColor === null) themeColor.removeAttribute('content');
      else themeColor.setAttribute('content', normalThemeColor);
    }
  };

  // Local diagnostics only: viewport gaps cannot be repaired by extending a DOM
  // element if iOS itself has reserved that area above the web view.
  window.sayFridgeBrowserDiagnostics = () => ({
    revision: 'status-bar-default-v4',
    userAgent: navigator.userAgent,
    standalone: !!navigator.standalone || matchMedia('(display-mode: standalone)').matches,
    statusBarStyle: document.querySelector('meta[name="apple-mobile-web-app-status-bar-style"]')?.content,
    viewportMeta: Array.from(document.querySelectorAll('meta[name="viewport"]'), meta => meta.content),
    screenHeight: screen.height,
    innerHeight,
    documentHeight: document.documentElement.clientHeight,
    visualViewportHeight: window.visualViewport?.height,
    visualViewportOffsetTop: window.visualViewport?.offsetTop,
    safeArea: window.sayFridgeReadSafeArea(),
    surfaceColor: getComputedStyle(document.getElementById('status-bar-surface')).backgroundColor,
  });

})();
