# Windows (PowerShell) setup: generates android/ and patches the manifest.
# Usage (in the project folder):  powershell -ExecutionPolicy Bypass -File tool\setup.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$utf8 = New-Object System.Text.UTF8Encoding $false
function Read-Utf8($p) { [IO.File]::ReadAllText((Resolve-Path $p), [Text.Encoding]::UTF8) }
function Write-Utf8($p, $t) { [IO.File]::WriteAllText((Resolve-Path $p), $t, $utf8) }

if (-not (Test-Path 'android')) {
    flutter create . --project-name meal_log --org com.masayuki.meallog --platforms android,ios
    if ($LASTEXITCODE -ne 0) { throw 'flutter create failed' }
    Remove-Item -ErrorAction SilentlyContinue 'test\widget_test.dart'
}

$manifest = 'android\app\src\main\AndroidManifest.xml'
$m = Read-Utf8 $manifest

if ($m -notmatch 'android\.permission\.INTERNET') {
    $m = [regex]::Replace($m, '(\s*<application)', "`n    <uses-permission android:name=`"android.permission.INTERNET`"/>`$1", 1)
}

$intent = "<intent>`n            <action android:name=`"android.intent.action.VIEW`"/>`n            <data android:scheme=`"https`"/>`n        </intent>"
if ($m -notmatch 'android:scheme="https"') {
    if ($m -match '<queries>') {
        $m = [regex]::Replace($m, '<queries>', "<queries>`n        $intent", 1)
    } else {
        $m = $m.Replace('</manifest>', "    <queries>`n        $intent`n    </queries>`n</manifest>")
    }
}

# App label: "食事記録" written with code points so this file stays ASCII
$label = [string]::new([char[]]@(0x98DF, 0x4E8B, 0x8A18, 0x9332))
$m = $m.Replace('android:label="meal_log"', "android:label=`"$label`"")

# ---------- Health Connect (read weight / body fat / steps / exercise) ----------
foreach ($perm in @('READ_WEIGHT', 'READ_BODY_FAT', 'READ_LEAN_BODY_MASS', 'READ_HEIGHT', 'READ_STEPS', 'READ_EXERCISE', 'READ_ACTIVE_CALORIES_BURNED', 'READ_DISTANCE', 'READ_HEALTH_DATA_HISTORY')) {
    if ($m -notmatch "android\.permission\.health\.$perm`"") {
        $m = [regex]::Replace($m, '(\s*<application)', "`n    <uses-permission android:name=`"android.permission.health.$perm`"/>`$1", 1)
    }
}
if ($m -notmatch 'com\.google\.android\.apps\.healthdata') {
    $m = [regex]::Replace($m, '</queries>', "    <package android:name=`"com.google.android.apps.healthdata`"/>`n    </queries>", 1)
}
if ($m -notmatch 'PermissionsRationaleActivity') {
    $rationale = @"
        <activity android:name=".PermissionsRationaleActivity" android:exported="true">
            <intent-filter>
                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
            </intent-filter>
        </activity>
        <activity-alias android:name="ViewPermissionUsageActivity" android:exported="true" android:targetActivity=".PermissionsRationaleActivity" android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE"/>
                <category android:name="android.intent.category.HEALTH_PERMISSIONS"/>
            </intent-filter>
        </activity-alias>
"@
    $m = [regex]::Replace($m, '(\s*</application>)', "`n$rationale`$1", 1)
}
# Reminder notifications and the home screen widget
if ($m -notmatch 'POST_NOTIFICATIONS') {
    $m = [regex]::Replace($m, '(\s*<application)', "`n    <uses-permission android:name=`"android.permission.POST_NOTIFICATIONS`"/>`$1", 1)
}
if ($m -notmatch 'ReminderReceiver') {
    $receivers = @"
        <receiver android:name=".ReminderReceiver" android:exported="false"/>
        <receiver android:name=".MealWidgetProvider" android:exported="false" android:label="$label">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/meal_widget_info"/>
        </receiver>
"@
    $m = [regex]::Replace($m, '(\s*</application>)', "`n$receivers`$1", 1)
}
Write-Utf8 $manifest $m

# Kotlin: replace MainActivity with the Health Connect version and add the rationale screen
$mainKt = Get-ChildItem -Recurse -Path 'android\app\src\main' -Filter 'MainActivity.kt' | Select-Object -First 1
$pkg = ([regex]::Match((Read-Utf8 $mainKt.FullName), '(?m)^package\s+(\S+)')).Groups[1].Value
$mainSrc = (Read-Utf8 'tool\android\MainActivity.kt').Replace('__PACKAGE__', $pkg)
[IO.File]::WriteAllText($mainKt.FullName, $mainSrc, $utf8)
$ratSrc = (Read-Utf8 'tool\android\PermissionsRationaleActivity.kt').Replace('__PACKAGE__', $pkg)
[IO.File]::WriteAllText((Join-Path $mainKt.DirectoryName 'PermissionsRationaleActivity.kt'), $ratSrc, $utf8)
foreach ($name in @('ReminderReceiver', 'MealWidgetProvider')) {
    $src = (Read-Utf8 "tool\android\$name.kt").Replace('__PACKAGE__', $pkg)
    [IO.File]::WriteAllText((Join-Path $mainKt.DirectoryName "$name.kt"), $src, $utf8)
}
foreach ($dir in @('layout', 'xml', 'drawable', 'values')) {
    New-Item -ItemType Directory -Force -Path "android\app\src\main\res\$dir" | Out-Null
    Copy-Item "tool\android\res\$dir\*" "android\app\src\main\res\$dir\" -Force
}

if (Test-Path 'android\app\build.gradle.kts') {
    $g = Read-Utf8 'android\app\build.gradle.kts'
    if ($g -notmatch 'connect-client') {
        $g += "`ndependencies {`n    implementation(`"androidx.health.connect:connect-client:1.1.0`")`n    implementation(`"org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1`")`n}`n"
        Write-Utf8 'android\app\build.gradle.kts' $g
    }
} elseif (Test-Path 'android\app\build.gradle') {
    $g = Read-Utf8 'android\app\build.gradle'
    if ($g -notmatch 'connect-client') {
        $g += "`ndependencies {`n    implementation `"androidx.health.connect:connect-client:1.1.0`"`n    implementation `"org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1`"`n}`n"
        Write-Utf8 'android\app\build.gradle' $g
    }
}

foreach ($f in @('android\app\build.gradle.kts', 'android\app\build.gradle')) {
    if (Test-Path $f) {
        $g = Read-Utf8 $f
        $g = $g -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 26'
        $g = $g -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 26'
        Write-Utf8 $f $g
    }
}

Write-Host 'setup done'
