{{flutter_js}}
{{flutter_build_config}}

// Keep Flutter's full-page viewport/keyboard behavior on touch devices.
const desktopBrowser = window.sayFridgeIsDesktopBrowser;

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
