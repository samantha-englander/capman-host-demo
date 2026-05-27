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
cp overlay/lib/features/session/data/demo_auth_service.dart \
   _capman_host/lib/features/session/data/demo_auth_service.dart
cp overlay/main_demo.dart               _capman_host/lib/main_demo.dart

echo "==> Installing Flutter dependencies..."
cd _capman_host
flutter pub get

echo "==> Running code generation..."
flutter pub run build_runner build --delete-conflicting-outputs

echo "==> Building Flutter Web..."
flutter build web \
  --target lib/main_demo.dart \
  --release \
  --dart-define=MOCK_SERVER_URL=${MOCK_SERVER_URL}

echo "==> Done. Output: _capman_host/build/web/"
