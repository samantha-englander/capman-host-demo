// Custom Flutter Web bootstrap for the Toast Tables demo.
// Mounts Flutter into #flutter-host (the tablet-frame inner screen) instead
// of the full browser viewport. Flutter reads the host element's dimensions
// for layout, so the app always behaves as if it's running on a tablet.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.querySelector('#flutter-host'),
    });
    await appRunner.runApp();
  }
});
