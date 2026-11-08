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
Write-Utf8 $manifest $m

foreach ($f in @('android\app\build.gradle.kts', 'android\app\build.gradle')) {
    if (Test-Path $f) {
        $g = Read-Utf8 $f
        $g = $g -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 26'
        $g = $g -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 26'
        Write-Utf8 $f $g
    }
}

Write-Host 'setup done'
