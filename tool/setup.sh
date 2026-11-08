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

# ---------- ヘルスコネクト（体重・体脂肪・歩数・運動の読み取り） ----------
# 読み取り権限
for perm in READ_WEIGHT READ_BODY_FAT READ_LEAN_BODY_MASS READ_HEIGHT READ_STEPS READ_EXERCISE READ_ACTIVE_CALORIES_BURNED READ_DISTANCE READ_HEALTH_DATA_HISTORY; do
  if ! grep -q "android.permission.health.$perm\"" "$MANIFEST"; then
    perl -0pi -e "s#(\\s*<application)#\\n    <uses-permission android:name=\"android.permission.health.$perm\"/>\$1#" "$MANIFEST"
  fi
done
# Android 13 以前でヘルスコネクトアプリを見つけるための queries
if ! grep -q 'com.google.android.apps.healthdata' "$MANIFEST"; then
  perl -0pi -e 's#</queries>#    <package android:name="com.google.android.apps.healthdata"/>\n    </queries>#' "$MANIFEST"
fi
# 権限の説明画面（Android 13 以前は intent-filter、14 以降は activity-alias で開かれる）
if ! grep -q 'PermissionsRationaleActivity' "$MANIFEST"; then
  RATIONALE='        <activity android:name=".PermissionsRationaleActivity" android:exported="true">\n            <intent-filter>\n                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>\n            </intent-filter>\n        </activity>\n        <activity-alias android:name="ViewPermissionUsageActivity" android:exported="true" android:targetActivity=".PermissionsRationaleActivity" android:permission="android.permission.START_VIEW_PERMISSION_USAGE">\n            <intent-filter>\n                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE"/>\n                <category android:name="android.intent.category.HEALTH_PERMISSIONS"/>\n            </intent-filter>\n        </activity-alias>\n'
  perl -0pi -e "s#(\\s*</application>)#\\n${RATIONALE}\$1#" "$MANIFEST"
fi
# Kotlin 側（MainActivity をヘルスコネクト対応版に置き換え、説明画面を追加）
MAIN_KT=$(find android/app/src/main -name MainActivity.kt | head -n 1)
PKG=$(sed -n 's/^package \(.*\)$/\1/p' "$MAIN_KT" | head -n 1)
KT_DIR=$(dirname "$MAIN_KT")
sed "s/__PACKAGE__/$PKG/" tool/android/MainActivity.kt > "$MAIN_KT"
sed "s/__PACKAGE__/$PKG/" tool/android/PermissionsRationaleActivity.kt > "$KT_DIR/PermissionsRationaleActivity.kt"
# ライブラリ
GRADLE_KTS=android/app/build.gradle.kts
GRADLE_GROOVY=android/app/build.gradle
if [ -f "$GRADLE_KTS" ] && ! grep -q 'connect-client' "$GRADLE_KTS"; then
  printf '\ndependencies {\n    implementation("androidx.health.connect:connect-client:1.1.0")\n    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")\n}\n' >> "$GRADLE_KTS"
elif [ -f "$GRADLE_GROOVY" ] && ! grep -q 'connect-client' "$GRADLE_GROOVY"; then
  printf '\ndependencies {\n    implementation "androidx.health.connect:connect-client:1.1.0"\n    implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1"\n}\n' >> "$GRADLE_GROOVY"
fi

# リリースビルドの縮小（R8）でヘルスコネクトの内部クラスが消されないようにする
PROGUARD=android/app/proguard-rules.pro
if ! grep -qs 'androidx.health' "$PROGUARD"; then
  printf '%s\n' '-keep class androidx.health.** { *; }' '-keep class android.health.connect.** { *; }' '-dontwarn androidx.health.**' >> "$PROGUARD"
fi

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
