#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/apps/android"
BUILD_DIR="$ROOT/.build/android"
OUT_DIR="$ROOT/release"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required. Install Flutter stable and the Android SDK first." >&2
  exit 2
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"
flutter create --platforms=android --org com.remim --project-name remim "$BUILD_DIR"
cp "$SOURCE/pubspec.yaml" "$BUILD_DIR/pubspec.yaml"
rm -rf "$BUILD_DIR/lib"
cp -R "$SOURCE/lib" "$BUILD_DIR/lib"
cp "$SOURCE/platform/AndroidManifest.xml" "$BUILD_DIR/android/app/src/main/AndroidManifest.xml"
cp "$SOURCE/platform/MainActivity.kt" "$BUILD_DIR/android/app/src/main/kotlin/com/remim/remim/MainActivity.kt"

cd "$BUILD_DIR"
flutter pub get
flutter build apk --release \
  --dart-define="SUPABASE_URL=${SUPABASE_URL:-}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT_DIR/Remim-Android-release.apk"
echo "APK created: $OUT_DIR/Remim-Android-release.apk"
