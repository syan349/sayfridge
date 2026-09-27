{{flutter_js}}
{{flutter_build_config}}

// Keep Flutter's full-page viewport/keyboard behavior on touch devices. Desktop
// browsers render into a resizable host, so every route stays inside the frame.
const desktopBrowser = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
if (desktopBrowser) {
  document.documentElement.classList.add('desktop-preview');
}

_flutter.loader.load({
  config: desktopBrowser
    ? { hostElement: document.getElementById('flutter-host') }
    : {},
});
