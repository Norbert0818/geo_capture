#requires -Version 5.1
[CmdletBinding()]
param([string]$DeviceId)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-GeoAdbDevices([string[]]$Lines) {
    foreach ($line in $Lines) {
        if ($line -match '^\s*(\S+)\s+(device|unauthorized|offline|recovery|sideload|bootloader)(?:\s+(.*))?$') {
            [pscustomobject]@{
                Id = $Matches[1]
                State = $Matches[2]
                Description = if ($Matches.ContainsKey(3)) { $Matches[3] } else { '' }
            }
        }
    }
}

function Get-GeoAndroidSdk([string]$PropertiesFile) {
    if (-not (Test-Path -LiteralPath $PropertiesFile -PathType Leaf)) { return $null }
    foreach ($line in [IO.File]::ReadAllLines($PropertiesFile)) {
        if ($line -match '^\s*sdk\.dir\s*=\s*(.+)$') {
            return $Matches[1].Trim().Replace('\:', ':').Replace('\\', '\')
        }
    }
    return $null
}

function Find-GeoAdb([string]$FlutterRoot) {
    $roots = @(
        (Get-GeoAndroidSdk (Join-Path $FlutterRoot 'android\local.properties')),
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT
    )
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $roots += Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    }
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $candidate = Join-Path $root 'platform-tools\adb.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    $command = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    throw 'Az adb.exe nem talalhato. Android Studio > SDK Manager > SDK Tools: telepitsd az Android SDK Platform-Tools csomagot. Egyedi SDK-mappanal ellenorizd az android/local.properties sdk.dir erteket.'
}

function New-GeoAndroidDefines([string]$PublicPem) {
    if ($PublicPem -notmatch '\A\s*-----BEGIN CERTIFICATE-----\s+[A-Za-z0-9+/=\s]+-----END CERTIFICATE-----\s*\z') {
        throw 'A fejlesztoi PEM fajl nem egyetlen nyilvanos tanusitvany. Privat kulcs nem kerulhet az alkalmazasba.'
    }
    return ([ordered]@{
        API_BASE_URL = 'https://localhost:7043'
        DEV_HTTPS_CERT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PublicPem))
    } | ConvertTo-Json)
}

function Assert-GeoApiHealth([string]$Url, [string]$ExpectedThumbprint) {
    $response = $null
    $reader = $null
    try {
        $request = [Net.HttpWebRequest]::Create($Url)
        $request.Proxy = $null
        $request.Timeout = 10000
        $request.ReadWriteTimeout = 10000
        $request.AllowAutoRedirect = $false
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200) { throw 'Az API nem 200-as valaszt adott.' }
        $serverCertificate = $request.ServicePoint.Certificate
        if ($null -eq $serverCertificate -or
            $serverCertificate.GetCertHashString() -ne $ExpectedThumbprint) {
            throw 'A futo API mas HTTPS-tanusitvanyt hasznal. Allitsd le a backendet, majd inditsd ujra a GeoCapture_inditas.bat fajllal.'
        }
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        $health = $reader.ReadToEnd() | ConvertFrom-Json
        if ($health.status -ne 'ok') { throw 'Az API health valasza nem megfelelo.' }
    }
    catch {
        throw ("Az ellenorzes sikertelen: $Url`n" +
            'A backend fusson Development modban a https://localhost:7043 cimen. ' +
            'A /health es /health/database oldalon is status: ok kell. ' +
            'HTTPS bizalmi hibanal ezen a gepen egyszer futtasd: dotnet dev-certs https --trust. ' +
            "Reszlet: $($_.Exception.Message)")
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

# Dot-sourcing makes the parsing helpers available to the launcher tests.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
    $flutterRoot = [IO.Path]::GetFullPath($PSScriptRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $flutterRoot 'pubspec.yaml') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $flutterRoot 'android') -PathType Container)) {
        throw 'Az inditofajlokat a Flutter-projekt gyokerebe masold: a pubspec.yaml es az android mappa melle.'
    }

    $flutter = Get-Command flutter -ErrorAction Stop
    $dotnet = Get-Command dotnet -ErrorAction Stop
    $adb = Find-GeoAdb $flutterRoot

    Write-Host 'Android-eszkozok keresese...' -ForegroundColor Cyan
    $deviceLines = @(& $adb devices -l)
    if ($LASTEXITCODE -ne 0) { throw 'Az adb devices parancs sikertelen.' }
    $allDevices = @(ConvertFrom-GeoAdbDevices $deviceLines)
    foreach ($item in $allDevices | Where-Object { $_.State -ne 'device' }) {
        Write-Host ($item.Id + ': ' + $item.State + ' - oldd fel a telefont, engedelyezd az USB debugging kapcsolatot.') -ForegroundColor Yellow
    }
    $devices = @($allDevices | Where-Object { $_.State -eq 'device' })
    if ($devices.Count -eq 0) {
        throw 'Nincs hasznalhato Android-eszkoz. Kapcsold be az USB debuggingot, hasznalj adatatvitelre alkalmas kabelt, es fogadd el a telefonon az engedelykerest. Vagy indits el egy Android-emulatort.'
    }

    if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
        $selected = @($devices | Where-Object { $_.Id -ceq $DeviceId })
        if ($selected.Count -ne 1) { throw 'A megadott DeviceId nem egy elerheto Android-eszkoz.' }
        $device = $selected[0]
    }
    elseif ($devices.Count -eq 1) { $device = $devices[0] }
    else {
        for ($index = 0; $index -lt $devices.Count; $index++) {
            Write-Host (('{0}. {1} {2}' -f ($index + 1), $devices[$index].Id, $devices[$index].Description))
        }
        $answer = Read-Host 'Melyik eszkoz? Ird be a sorszamat'
        $selection = 0
        if (-not [int]::TryParse($answer, [ref]$selection) -or
            $selection -lt 1 -or $selection -gt $devices.Count) {
            throw 'Ervenytelen eszkozvalasztas.'
        }
        $device = $devices[$selection - 1]
    }

    Push-Location -LiteralPath $flutterRoot
    try {
        Write-Host 'Flutter-fuggosegek ellenorzese...' -ForegroundColor Cyan
        & $flutter.Source pub get
        if ($LASTEXITCODE -ne 0) { throw 'A flutter pub get sikertelen.' }

        $settingsRoot = Join-Path $flutterRoot '.dart_tool\geocapture'
        [void][IO.Directory]::CreateDirectory($settingsRoot)
        $certificateFile = Join-Path $settingsRoot 'android-localhost-public.pem'
        $definesFile = Join-Path $settingsRoot 'android.debug.json'

        Write-Host 'A helyi HTTPS-tanusitvany nyilvanos reszenek exportalasa...' -ForegroundColor Cyan
        & $dotnet.Source dev-certs https --export-path $certificateFile --format PEM
        if ($LASTEXITCODE -ne 0) { throw 'A dotnet dev-certs export sikertelen.' }
        $pem = [IO.File]::ReadAllText($certificateFile)
        $defines = New-GeoAndroidDefines $pem
        $der = [Convert]::FromBase64String(($pem -replace '-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s', ''))
        $publicCertificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$der)
        try {
            Write-Host 'API es adatbazis ellenorzese...' -ForegroundColor Cyan
            Assert-GeoApiHealth 'https://localhost:7043/health' $publicCertificate.Thumbprint
            Assert-GeoApiHealth 'https://localhost:7043/health/database' $publicCertificate.Thumbprint
        }
        finally { $publicCertificate.Dispose() }
        [IO.File]::WriteAllText($definesFile, $defines, (New-Object Text.UTF8Encoding($false)))

        Write-Host ('USB porttovabbitas: ' + $device.Id) -ForegroundColor Cyan
        & $adb -s $device.Id reverse tcp:7043 tcp:7043
        if ($LASTEXITCODE -ne 0) { throw 'Az adb reverse sikertelen.' }

        Write-Host 'Android-alkalmazas inditasa. Leallitas: q; hot reload: r.' -ForegroundColor Green
        & $flutter.Source run --debug -d $device.Id "--dart-define-from-file=$definesFile"
        if ($LASTEXITCODE -ne 0) { throw 'A Flutter Android-futtatasa sikertelen. Lasd a fenti hibat.' }
    }
    finally { Pop-Location }
    exit 0
}
catch {
    Write-Host ('HIBA: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}