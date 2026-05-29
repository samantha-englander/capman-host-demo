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
# Replace ONLY the final _flutter.loader.load(...) invocation in the file.
# The inlined Flutter loader script contains internal references to .load that
# must NOT be modified, or we end up with double engine initialization.
# Python rsplit guarantees only the last occurrence is rewritten.
python3 <<'PYEOF'
import re
path = 'build/web/flutter_bootstrap.js'
with open(path) as f:
    content = f.read()

# Find the LAST `_flutter.loader.load(...)` call — that's the public entrypoint.
# Match the call and any existing arguments inside the parens.
pattern = re.compile(r'_flutter\.loader\.load\([^)]*\)\s*;?\s*$', re.MULTILINE)
matches = list(pattern.finditer(content))
if matches:
    last = matches[-1]
    replacement = (
        '_flutter.loader.load({'
        'onEntrypointLoaded:async function(e){'
        'var a=await e.initializeEngine({hostElement:document.querySelector("#flutter-host")});'
        'await a.runApp();'
        '}'
        '});'
    )
    content = content[:last.start()] + replacement + content[last.end():]
    with open(path, 'w') as f:
        f.write(content)
    print(f'    OK — patched last loader call at offset {last.start()}.')
else:
    print('    WARNING: no _flutter.loader.load(...) match found; frame may not work.')
PYEOF

echo "==> Stamping build sha + timestamp into index.html..."
# Sha comes from the DEMO repo HEAD (one dir up from _capman_host, since
# we cd'd into the clone earlier). That's what actually changes between
# deploys — capman-host itself is a fresh shallow clone every run.
BUILD_SHA=$(git -C .. rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME=$(date -u +"%Y-%m-%d %H:%M UTC")
sed -i "s|__BUILD_SHA__|${BUILD_SHA}|g" build/web/index.html
sed -i "s|__BUILD_TIME__|${BUILD_TIME}|g" build/web/index.html
echo "    OK — build ${BUILD_SHA} @ ${BUILD_TIME}"

echo "==> Patching login button text for demo..."
sed -i 's/Login with your Toast account/Start Demo/g' build/web/main.dart.js

echo "==> Patching 'Trouble logging in?' link to 'Learn More' + new URL..."
sed -i 's/Trouble logging in?/Learn More/g' build/web/main.dart.js
sed -i 's|https://support.toasttab.com/en/article/Get-Help-with-Toast-Tables-Issues-Logging-in-to-the-Toast-Tables-App|https://pos.toasttab.com/products/toast-tables?srsltid=AfmBOopilVglmSYpG6S4hAgRkLWdrRT3FlGWRs3wA42VLGqR2zk6OtBb|g' build/web/main.dart.js

echo "==> Done. Output: _capman_host/build/web/"
