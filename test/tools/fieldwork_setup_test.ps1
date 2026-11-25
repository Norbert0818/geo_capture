#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../geocapture_fieldwork_setup.ps1')
$script:passed = 0
function Check([string]$Name, [scriptblock]$Test) { & $Test; $script:passed++; Write-Host ('PASS: ' + $Name) }
function Assert([bool]$Value) { if (-not $Value) { throw 'Assertion failed.' } }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('geo-fieldwork-' + [Guid]::NewGuid().ToString('N'))
$sdk = Join-Path $temporary 'android'
[void][IO.Directory]::CreateDirectory((Join-Path $sdk 'app'))
[void][IO.Directory]::CreateDirectory((Join-Path $sdk 'gradle/wrapper'))
$settings = Join-Path $sdk 'settings.gradle.kts'
$app = Join-Path $sdk 'app/build.gradle.kts'
$wrapper = Join-Path $sdk 'gradle/wrapper/gradle-wrapper.properties'
try {
    [IO.File]::WriteAllText($settings, 'plugins { id("com.android.application") version "8.9.1" apply false; id("org.jetbrains.kotlin.android") version "2.1.0" apply false }')
    [IO.File]::WriteAllText($wrapper, 'distributionUrl=https\://services.gradle.org/distributions/gradle-8.12-all.zip')
    [IO.File]::WriteAllText($app, "android {`n    compileSdk = flutter.compileSdkVersion`n    defaultConfig {`n        minSdk = flutter.minSdkVersion // retained comment`n    }`n}")
    Check 'Finds the three required compatibility changes' {
        Assert (@(Get-GeoFieldworkAndroidPlan $temporary).Count -eq 3)
    }
    Check 'Updates minimum versions and preserves Flutter expressions' {
        Write-GeoFieldworkAndroidPlan @(Get-GeoFieldworkAndroidPlan $temporary)
        Assert ([IO.File]::ReadAllText($settings).Contains('8.12.1'))
        Assert ([IO.File]::ReadAllText($settings).Contains('2.2.0'))
        Assert ([IO.File]::ReadAllText($wrapper).Contains('gradle-8.13-all.zip'))
        Assert ([IO.File]::ReadAllText($app).Contains('maxOf(36, flutter.compileSdkVersion)'))
        Assert ([IO.File]::ReadAllText($app).Contains('maxOf(24, flutter.minSdkVersion) // retained comment'))
    }
    Check 'Running again does not change files again' { Assert (@(Get-GeoFieldworkAndroidPlan $temporary).Count -eq 0) }
    Check 'Keeps a backup without overwriting it' {
        Assert ([IO.File]::ReadAllText($settings + '.before-fieldwork').Contains('8.9.1'))
        Write-GeoFieldworkAndroidPlan @(Get-GeoFieldworkAndroidPlan $temporary)
        Assert ([IO.File]::ReadAllText($settings + '.before-fieldwork').Contains('8.9.1'))
    }
    Check 'Does not downgrade newer versions or numeric SDK levels' {
        [IO.File]::WriteAllText($settings, 'plugins { id("com.android.application") version "9.1.0" apply false; id("org.jetbrains.kotlin.android") version "2.3.0" apply false }')
        [IO.File]::WriteAllText($wrapper, "distributionUrl=https\://services.gradle.org/distributions/gradle-9.1.0-bin.zip`ndistributionSha256Sum=keep-existing-checksum")
        [IO.File]::WriteAllText($app, "android {`n compileSdk = 37`n defaultConfig {`n minSdk = 26`n }`n}")
        Assert (@(Get-GeoFieldworkAndroidPlan $temporary).Count -eq 0)
    }
    Check 'Updates a pinned checksum together with its Gradle distribution' {
        [IO.File]::WriteAllText($wrapper, "distributionUrl=https\://services.gradle.org/distributions/gradle-8.12-all.zip`ndistributionSha256Sum=old-checksum")
        Write-GeoFieldworkAndroidPlan @(Get-GeoFieldworkAndroidPlan $temporary)
        Assert ([IO.File]::ReadAllText($wrapper).Contains('distributionSha256Sum=fba8464465835e74f7270bbf43d6d8a8d7709ab0a43ce1aa3323f73e9aa0c612'))
    }
    Check 'Missing Android configuration fails before any writes' {
        $old = [IO.File]::ReadAllText($settings)
        Remove-Item -LiteralPath $app
        $caught = $false
        try { Get-GeoFieldworkAndroidPlan $temporary } catch { $caught = $true }
        Assert $caught
        Assert ([IO.File]::ReadAllText($settings) -ceq $old)
    }
}
finally { Remove-Item -LiteralPath $temporary -Force -Recurse }
Write-Host ('Fieldwork Android setup tests passed: ' + $script:passed)