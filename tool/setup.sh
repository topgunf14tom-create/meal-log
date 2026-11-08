#!/usr/bin/env bash
# Android / iOS のプラットフォームフォルダを生成し、必要な設定を追記する。
# 何度実行しても同じ結果になる（冪等）。GitHub Actions・Mac・Git Bash で使用。
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create . --project-name meal_log --org com.masayuki.meallog --platforms android,ios
  # flutter create が作るサンプルテストは本アプリと合わないので削除
  rm -f test/widget_test.dart
fi

MANIFEST=android/app/src/main/AndroidManifest.xml

# インターネット権限（リリースビルドでは既定で付かない）
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  perl -0pi -e 's#(\s*<application)#\n    <uses-permission android:name="android.permission.INTERNET"/>$1#' "$MANIFEST"
fi

# 外部ブラウザで https を開くための queries（Android 11+）
if ! grep -q 'android:scheme="https"' "$MANIFEST"; then
  HTTPS_INTENT='<intent>\n            <action android:name="android.intent.action.VIEW"/>\n            <data android:scheme="https"/>\n        </intent>'
  if grep -q '<queries>' "$MANIFEST"; then
    perl -0pi -e "s#<queries>#<queries>\n        ${HTTPS_INTENT}#" "$MANIFEST"
  else
    perl -0pi -e "s#</manifest>#    <queries>\n        ${HTTPS_INTENT}\n    </queries>\n</manifest>#" "$MANIFEST"
  fi
fi

# アプリ名
perl -pi -e 's/android:label="meal_log"/android:label="食事記録"/' "$MANIFEST"

# minSdk 26
for f in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$f" ]; then
    perl -pi -e 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 26/; s/minSdkVersion\s+flutter\.minSdkVersion/minSdkVersion 26/' "$f"
  fi
done

# iOS：カメラ・写真ライブラリの利用目的
PLIST=ios/Runner/Info.plist
if [ -f "$PLIST" ] && ! grep -q 'NSCameraUsageDescription' "$PLIST"; then
  perl -0pi -e 's#</dict>\s*</plist>\s*$#\t<key>NSCameraUsageDescription</key>\n\t<string>食事の写真を撮影するために使用します</string>\n\t<key>NSPhotoLibraryUsageDescription</key>\n\t<string>食事の写真を選択するために使用します</string>\n</dict>\n</plist>\n#' "$PLIST"
  perl -pi -e 's/<string>Meal Log<\/string>/<string>食事記録<\/string>/' "$PLIST"
fi

echo "setup done"
