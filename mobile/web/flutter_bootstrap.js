{{flutter_js}}
{{flutter_build_config}}

// Keep Flutter's full-page viewport/keyboard behavior on touch devices. Desktop
// browsers render into a resizable host, so every route stays inside the frame.
const desktopBrowser = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
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

const engineConfig = desktopBrowser
  ? { hostElement: document.getElementById('flutter-host') }
  : {};

_flutter.loader.load({
  config: engineConfig,
  onEntrypointLoaded: async engineInitializer => {
    const appRunner = await engineInitializer.initializeEngine(engineConfig);
    if (!desktopBrowser) {
      // Full-page embedding replaces the viewport when the first view is made,
      // including on hot restart. Keep cover on the engine-created viewport.
      const ensureFullScreenViewport = () => {
        const viewport = document.querySelector('meta[name="viewport"]');
        if (viewport && !viewport.content.includes('viewport-fit=cover')) {
          viewport.content = viewport.content.replace(/,?\s*viewport-fit=[^,]+/, '')
            + ', viewport-fit=cover';
        }
      };
      new MutationObserver(ensureFullScreenViewport).observe(document.head, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['content'],
      });
      ensureFullScreenViewport();
    }
    await appRunner.runApp();
  },
});
