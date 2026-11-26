# 一键构建 AI 成片 APK（自动命名为 app-video.apk，绝不碰数学 App 的 app-release.apk）
param([switch]$Clean)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$env:JAVA_HOME = "G:\dev\jdk17"
$env:ANDROID_HOME = "G:\dev\android-sdk"
$env:ANDROID_SDK_ROOT = "G:\dev\android-sdk"
# 国内镜像：不加这个，Flutter 引擎产物会卡死
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PATH = "$env:JAVA_HOME\bin;G:\dev\flutter\bin;$env:PATH"

if ($Clean) { Write-Host "清理中..." -ForegroundColor Yellow; flutter clean }

Write-Host "开始构建..." -ForegroundColor Cyan
flutter build apk --release --no-pub
if ($LASTEXITCODE -ne 0) { Write-Host "构建失败" -ForegroundColor Red; exit 1 }

$apkDir = Join-Path $root "build\app\outputs\flutter-apk"
$src = Join-Path $apkDir "app-release.apk"
if (-not (Test-Path $src)) {
    $alt = Join-Path $root "build\app\outputs\apk\release\app-release.apk"
    if (Test-Path $alt) { $src = $alt } else { Write-Host "没找到 APK" -ForegroundColor Red; exit 1 }
}

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$dst = Join-Path $dist "app-video.apk"
Copy-Item $src $dst -Force
if (Test-Path $apkDir) { Copy-Item $src (Join-Path $apkDir "app-video.apk") -Force -ErrorAction SilentlyContinue }

$mb = [math]::Round((Get-Item $dst).Length / 1MB, 1)
Write-Host "" 
Write-Host ("完成: " + $dst + "  (" + $mb + " MB)") -ForegroundColor Green
