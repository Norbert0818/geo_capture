#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\geocapture_android.ps1')

$passed = 0
function Assert-GeoEqual($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw ("FAIL: $Message - expected: $Expected, actual: $Actual") }
    $script:passed++
    Write-Host ("PASS: $Message") -ForegroundColor Green
}

$devices = @(ConvertFrom-GeoAdbDevices @(
    'List of devices attached',
    '* daemon started successfully',
    'ABC123 device usb:1-2 product:phone model:Test_phone transport_id:1',
    'emulator-5554 device product:sdk model:Android_Emulator transport_id:2',
    'WAIT123 unauthorized usb:1-3 transport_id:3',
    'OLD123 offline transport_id:4',
    ''
))
Assert-GeoEqual $devices.Count 4 'Ignores headers and daemon messages'
Assert-GeoEqual (@($devices | Where-Object { $_.State -eq 'device' }).Count) 2 'Does not treat unauthorized or offline devices as ready'
Assert-GeoEqual $devices[0].Id 'ABC123' 'Preserves the physical device id'
Assert-GeoEqual $devices[1].Id 'emulator-5554' 'Preserves the emulator id'
Assert-GeoEqual (@(ConvertFrom-GeoAdbDevices @('List of devices attached', '')).Count) 0 'Handles no attached device'

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('geocapture-launcher-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
try {
    $properties = Join-Path $temporary 'local.properties'
    [IO.File]::WriteAllText($properties, "# Android Studio settings`nsdk.dir=E\:\\Android SDK\\sdk`nflutter.sdk=C\:\\flutter`n")
    Assert-GeoEqual (Get-GeoAndroidSdk $properties) 'E:\Android SDK\sdk' 'Reads an escaped SDK path containing spaces on another drive'
    Assert-GeoEqual (Get-GeoAndroidSdk (Join-Path $temporary 'missing.properties')) $null 'Missing local.properties uses SDK discovery fallback'

    $fixture = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\core\api\tls_fixture.dart'))
    $pem = [regex]::Match($fixture, '-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----').Value
    $settings = New-GeoAndroidDefines $pem | ConvertFrom-Json
    Assert-GeoEqual $settings.API_BASE_URL 'https://localhost:7043' 'Uses the USB-forwarded HTTPS origin'
    $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($settings.DEV_HTTPS_CERT_BASE64))
    Assert-GeoEqual $decoded $pem 'Transfers exactly the public certificate'
    Assert-GeoEqual (@($settings.PSObject.Properties).Count) 2 'Does not add database or private-key settings'

    $rejected = $false
    try { [void](New-GeoAndroidDefines ($pem + "`n-----BEGIN PRIVATE KEY-----`nAAAA`n-----END PRIVATE KEY-----")) }
    catch { $rejected = $true }
    Assert-GeoEqual $rejected $true 'Rejects a PEM containing a private key'
}
finally { Remove-Item -LiteralPath $temporary -Recurse -Force }

Write-Host ("Android launcher checks passed: $passed") -ForegroundColor Green