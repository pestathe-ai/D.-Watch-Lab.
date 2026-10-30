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

# Apertura link nel browser (Android 11+)
if ! grep -q 'android:scheme="https"' "$MANIFEST"; then
  if grep -q '<queries>' "$MANIFEST"; then
    sed -i 's#<queries>#<queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW" />\n            <data android:scheme="https" />\n        </intent>#' "$MANIFEST"
  else
    sed -i 's#</manifest>#    <queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW" />\n            <data android:scheme="https" />\n        </intent>\n    </queries>\n</manifest>#' "$MANIFEST"
  fi
fi

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
# Icona dell'app (stile Marchio dom)
dart run flutter_launcher_icons
echo "--- manifest ---"; cat "$MANIFEST"
grep -n "minSdk" android/app/build.gradle* || true
