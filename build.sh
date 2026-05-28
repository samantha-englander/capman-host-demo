#!/bin/bash
set -e

echo "==> Cloning capman-host..."
rm -rf _capman_host
git clone --depth 1 \
  https://x-access-token:${TOAST_GITHUB_TOKEN}@github.toasttab.com/toasttab/capman-host.git \
  _capman_host

echo "==> Injecting overlay files..."
cp overlay/lib/di/env.dart              _capman_host/lib/di/env.dart
cp overlay/lib/di/networking_module.dart _capman_host/lib/di/networking_module.dart
cp overlay/lib/di/auth_module.dart      _capman_host/lib/di/auth_module.dart
cp overlay/lib/di/launchdarkly_module.dart _capman_host/lib/di/launchdarkly_module.dart
cp overlay/lib/di/plugin_module.dart    _capman_host/lib/di/plugin_module.dart
cp overlay/lib/shared_ui/bloc/app_config/app_config_module.dart \
   _capman_host/lib/shared_ui/bloc/app_config/app_config_module.dart
cp overlay/lib/shared_data/networking/cloud_sync/grpc_module.dart \
   _capman_host/lib/shared_data/networking/cloud_sync/grpc_module.dart
cp overlay/web/index.html \
   _capman_host/web/index.html
cp overlay/lib/features/session/data/demo_auth_service.dart \
   _capman_host/lib/features/session/data/demo_auth_service.dart
cp overlay/lib/shared_data/networking/interceptor/demo_mock_interceptor.dart \
   _capman_host/lib/shared_data/networking/interceptor/demo_mock_interceptor.dart
cp overlay/lib/shared_data/services/demo_feature_flag_service.dart \
   _capman_host/lib/shared_data/services/demo_feature_flag_service.dart
cp overlay/lib/entry_point.dart         _capman_host/lib/entry_point.dart
cp overlay/main_demo.dart               _capman_host/lib/main_demo.dart

echo "==> Configuring git for HTTPS access to Toast GitHub..."
git config --global url."https://x-access-token:${TOAST_GITHUB_TOKEN}@github.toasttab.com/".insteadOf "git@github.toasttab.com:"

echo "==> Installing Flutter dependencies..."
cd _capman_host
flutter pub get

echo "==> Generating localizations..."
flutter pub run intl_utils:generate

echo "==> Running code generation..."
flutter pub run build_runner build --delete-conflicting-outputs

echo "==> Building Flutter Web..."
flutter build web \
  --target lib/main_demo.dart \
  --release \
  --base-href /capman-host-demo/

echo "==> Patching flutter_bootstrap.js to mount Flutter inside tablet-frame host element..."
# Flutter generates build/web/flutter_bootstrap.js with a bare _flutter.loader.load() call.
# We replace it with the hostElement config so Flutter mounts into #flutter-host (the tablet
# screen area) rather than the full browser viewport.
if grep -q '_flutter\.loader\.load()' build/web/flutter_bootstrap.js; then
  sed -i 's/_flutter\.loader\.load()/_flutter.loader.load({config:{hostElement:document.querySelector("#flutter-host")}})/g' build/web/flutter_bootstrap.js
  echo "    OK — hostElement config injected."
else
  echo "    WARNING: expected pattern not found; trying legacy onEntrypointLoaded form..."
  # Fallback: append a small override script if the generated file uses a different form
  cat >> build/web/flutter_bootstrap.js << 'ENDPATCH'

// Demo tablet-frame patch: re-run loader with hostElement if not already set
if (window._flutter && window._flutter.loader) {
  window._flutter.loader.load({
    onEntrypointLoaded: async function(engineInitializer) {
      const appRunner = await engineInitializer.initializeEngine({
        hostElement: document.querySelector('#flutter-host'),
      });
      await appRunner.runApp();
    }
  });
}
ENDPATCH
  echo "    Appended fallback hostElement patch."
fi

echo "==> Patching login button text for demo..."
sed -i 's/Login with your Toast account/Start Demo/g' build/web/main.dart.js

echo "==> Done. Output: _capman_host/build/web/"
