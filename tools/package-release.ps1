<#
.SYNOPSIS
    Packages Pulgapp Windows Server and Android Client for release distribution.
.DESCRIPTION
    Builds the self-contained Windows x64 WPF server and zips it,
    then builds the Android APK and outputs both artifacts to the 'release/' folder.
#>

param(
    [string]$Configuration = "Release",
    [switch]$SkipMobile,
    [switch]$SkipWindows
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ReleaseDir = Join-Path $RepoRoot "release"
$BuildDir = Join-Path $RepoRoot "build"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Pulgapp Release Packaging Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Repository root: $RepoRoot"
Write-Host "Output directory: $ReleaseDir"

if (-not (Test-Path $ReleaseDir)) {
    New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null
}

# 1. Package Windows Server
if (-not $SkipWindows) {
    Write-Host "`n[1/2] Building Windows Host (x64 self-contained)..." -ForegroundColor Yellow
    $WinPublishDir = Join-Path $BuildDir "windows-publish"
    if (Test-Path $WinPublishDir) {
        Remove-Item -Recurse -Force $WinPublishDir
    }

    $ProjectFile = Join-Path $RepoRoot "windows/src/Pulgapp.Server.App/Pulgapp.Server.App.csproj"
    dotnet publish $ProjectFile `
        --configuration $Configuration `
        -r win-x64 `
        --self-contained true `
        -p:PublishSingleFile=false `
        -o $WinPublishDir

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Windows publish failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }

    $WinZipFile = Join-Path $ReleaseDir "Pulgapp-Server-win-x64.zip"
    if (Test-Path $WinZipFile) {
        Remove-Item -Force $WinZipFile
    }

    Write-Host "Compressing to $WinZipFile..." -ForegroundColor Gray
    Compress-Archive -Path "$WinPublishDir\*" -DestinationPath $WinZipFile -CompressionLevel Optimal
    Write-Host "Windows package ready: $WinZipFile" -ForegroundColor Green
}

# 2. Package Mobile Client (Android)
if (-not $SkipMobile) {
    Write-Host "`n[2/2] Building Android Client APK..." -ForegroundColor Yellow
    $MobileDir = Join-Path $RepoRoot "mobile"
    
    Push-Location $MobileDir
    try {
        # Build debug APK for testing (no keystore needed)
        flutter build apk --debug --no-pub
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Flutter build failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }

        $SourceApk = Join-Path $MobileDir "build/app/outputs/flutter-apk/app-debug.apk"
        $TargetApk = Join-Path $ReleaseDir "Pulgapp-Android.apk"
        
        Copy-Item -Path $SourceApk -Destination $TargetApk -Force
        Write-Host "Android package ready: $TargetApk" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Packaging Completed Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Get-ChildItem -Path $ReleaseDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
