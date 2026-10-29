#!/usr/bin/env bash
# Genera le cartelle android/ e ios/ (non versionate) e applica le patch.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --project-name d_watch_lab --org dev.dwatchlab --platforms=android,ios . >/dev/null
rm -f test/widget_test.dart

# Nome visibile dell'app
MANIFEST=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="[^"]*"/android:label="D. Watch Lab"/' "$MANIFEST"
# Internet (serve in release)
grep -q 'android.permission.INTERNET' "$MANIFEST" || \
  sed -i 's#<manifest xmlns:android="http://schemas.android.com/apk/res/android">#<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET"/>#' "$MANIFEST"

# minSdk 24 (richiesto dai plugin)
for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] && sed -i -E 's/minSdk(Version)? *=? *flutter\.minSdkVersion/minSdk = 24/' "$f" || true
done

# iOS: permessi foto/fotocamera (solo su macOS)
if [ "$(uname)" = "Darwin" ]; then
  PL=ios/Runner/Info.plist
  /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 'Per fotografare il tuo orologio'" "$PL" || true
  /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryUsageDescription string 'Per scegliere le foto del tuo orologio'" "$PL" || true
fi

flutter pub get
echo "--- manifest ---"; cat "$MANIFEST" | head -12
grep -n "minSdk" android/app/build.gradle* || true
