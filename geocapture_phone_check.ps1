#requires -Version 5.1
[CmdletBinding()]
param([string]$DeviceId, [string]$ApplicationId)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-GeoQaApplicationId([string]$Value) {
    return $Value -cmatch '\A[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\z'
}

function Get-GeoQaApplicationId([string]$GradleText) {
    $pattern = '(?m)^\s*applicationId\s*(?:=\s*)?["'']([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)["'']\s*;?\s*(?://[^\r\n]*)?$'
    if ($GradleText -match $pattern) { return $Matches[1] }
    return $null
}

function Get-GeoQaLauncher([string[]]$Lines, [string]$Package) {
    foreach ($line in $Lines) {
        $value = $line.Trim()
        if ($value -cmatch '\A([A-Za-z_][A-Za-z0-9_.]*)/([A-Za-z_.$][A-Za-z0-9_.$]*)\z' -and
                $Matches[1] -ceq $Package) { return $value }
    }
    return $null
}

function Get-GeoQaCases {
    @(
        [pscustomobject]@{ Id='camera'; Title='Kamera es koordinatak'; Action='none'; Prepare=''; Verify='Keszits ket fotot. Ellenorizd a teljes kepernyos kamerat, az allithato sotetitest, az elerheto gombokat es a nagyobb, hat tizedesjegyes koordinatakat. A helyi mentes fejezodjon be.' },
        [pscustomobject]@{ Id='serials'; Title='Regi es uj szeriaszam'; Action='none'; Prepare=''; Verify='Az Upload photos utan toltsd ki mindket szeriaszamot, peldaul OLD-0000123 es NEW-0000456 ertekkel. Cancel-lel zarj vissza. Ujranyitas utan mindket ertek maradjon meg. Zard vissza az ablakot es vard meg a helyi mentest.' },
        [pscustomobject]@{ Id='restart'; Title='Piszkozatok ujrainditas utan'; Action='restart'; Prepare='A ket foto legyen helyileg elmentve, es a szeriaszamablak legyen bezarva. Most az alkalmazas folyamata leall es ujraindul.'; Verify='Szukseg eseten jelentkezz be ugyanazzal a fiokkal. Mindket foto, az eredeti es koordinatas valtozat, a GPS-adatok es a ket szeriaszam legyen meg.' },
        [pscustomobject]@{ Id='delete'; Title='Foto torlesenek megorzese'; Action='restart'; Prepare='Torold az egyik helyi fotot, zard be a fotopanelt, es vard meg a helyi mentes veget. Ezutan ujrainditjuk az alkalmazast.'; Verify='Bejelentkezes utan csak a megmaradt foto legyen lathato. Ne jojjon vissza a torolt foto.' },
        [pscustomobject]@{ Id='offline'; Title='Megszakadt API-kapcsolat'; Action='offline'; Prepare='Legyel bejelentkezve, egy helyileg elmentett fotoval. Meg mukodo API-val nyisd meg az Upload photos ablakot, ellenorizd a ket szamot, majd Cancel-lel zard be es vard meg a mentest. A telefont hagyd nyitva. Ezutan a BACKEND SAJAT konzolablakaban Ctrl+C-vel allitsd le az API-t: ez bontja a mar nyitott kapcsolatokat is. A szeriaszamokat majd a telefonon add meg.'; Verify='Nyomd meg az Upload photos gombot, add meg mindket szamot es varj a halozati hibara. A foto maradjon meg, jelenjen meg az ujraprobalas lehetosege. A valaszod utan az USB-port visszaall; a kovetkezo lepeshez a backendet ujra el kell inditanod.' },
        [pscustomobject]@{ Id='resume'; Title='Feltoltes folytatasa'; Action='restart'; Prepare='Inditsd ujra a BACKENDET a korabbi inditasoddal. A telefonos alkalmazas fuggoben levo csomagjat ne modositsd. Most ellenorizzuk az API-t es ujrainditjuk az alkalmazast. Ha az elozo probat kihagytad, ezt is jelold kihagyottnak.'; Verify='Jelentkezz be ugyanazzal a fiokkal. A foto es a ket szeriaszam legyen meg. Retry upload utan egyszer mentodjon a feltoltes, a helyi lista pedig uruljon ki.' },
        [pscustomobject]@{ Id='stored'; Title='Mentett kepek visszanezese'; Action='none'; Prepare=''; Verify='A My uploads listaban es a reszleteknel legyen regi es uj szeriaszam. Nyisd meg az eredeti es koordinatas kepet: a koordinatafelirat csak a koordinatas kepen legyen, a kamera sotet savjai egyik mentett kepre se keruljenek ra. Ellenorizd az idopontot es GPS-pontossagot is.' },
        [pscustomobject]@{ Id='accounts'; Title='Helyi fiokok elkulonitese'; Action='none'; Prepare=''; Verify='Az elso fiokban keszits egy uj fotot es vard meg a helyi mentest. Jelentkezz ki es lepj be masik fiokkal: az elso fiok helyi fotoja ne jelenjen meg. Az elso fiokba visszalepve annak fotoja ismet legyen meg.' },
        [pscustomobject]@{ Id='roles'; Title='Normal es admin hozzaferes'; Action='none'; Prepare=''; Verify='Normal fiokban csak a sajat feltoltesek listaja legyen elerheto. Adminkent az All uploads mutassa a masik felhasznalo feltolteset is, mindket szeriaszammal es a kepek reszleteivel.' }
    )
}

function Get-GeoQaSummary([object[]]$Cases, [Collections.IDictionary]$Results, [string]$RuntimeError) {
    $pass = 0; $fail = 0; $skip = 0; $pending = 0
    foreach ($case in $Cases) {
        if (-not $Results.Contains($case.Id)) { $pending++; continue }
        switch ($Results[$case.Id]) {
            'PASS' { $pass++ }
            'FAIL' { $fail++ }
            'SKIP' { $skip++ }
            default { throw 'Ervenytelen teszteredmeny.' }
        }
    }
    $state = if (-not [string]::IsNullOrWhiteSpace($RuntimeError)) { 'ABORTED' }
    elseif ($fail -gt 0) { 'FAILED' }
    elseif ($skip -gt 0 -or $pending -gt 0) { 'INCOMPLETE' }
    else { 'PASSED' }
    [pscustomobject]@{ State=$state; Passed=$pass; Failed=$fail; Skipped=$skip; Pending=$pending }
}

function Write-GeoQaReport([string]$Path, [object[]]$Cases, [Collections.IDictionary]$Results,
                           [string]$Model, [string]$Package, [string]$RuntimeError) {
    $summary = Get-GeoQaSummary $Cases $Results $RuntimeError
    $lines = @(
        '# GeoCapture - telefonos proba', '',
        ('Idopont: ' + [DateTimeOffset]::Now.ToString('o')),
        ('Telefonmodell: ' + ($Model -replace '[\r\n|]', ' ')),
        ('Alkalmazas: ' + $Package),
        'API: https://localhost:7043', '',
        'Az API- es adatbazis-eleres automatikusan ellenorzott. Az alabbi funkciok eredmenyet a telefont hasznalo szemely jelolte.', '',
        ('Allapot: ' + $summary.State),
        ('PASS: {0}; FAIL: {1}; SKIP: {2}; NOT_RUN: {3}' -f $summary.Passed, $summary.Failed, $summary.Skipped, $summary.Pending), '',
        '| Proba | Eredmeny |', '| --- | --- |'
    )
    foreach ($case in $Cases) {
        $result = if ($Results.Contains($case.Id)) { $Results[$case.Id] } else { 'NOT_RUN' }
        $lines += ('| {0} | {1} |' -f $case.Title, $result)
    }
    if (-not [string]::IsNullOrWhiteSpace($RuntimeError)) { $lines += @('', 'Futtatasi hiba:', '', $RuntimeError) }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, ($lines -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}

function Invoke-GeoQaNetworkPause([scriptblock]$Disconnect, [scriptblock]$Verify, [scriptblock]$Reconnect) {
    try { & $Disconnect; & $Verify }
    finally { & $Reconnect }
}

function Test-GeoQaTcpAvailable([string]$ServerHost = 'localhost', [int]$Port = 7043) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $connecting = $client.ConnectAsync($ServerHost, $Port)
        if (-not $connecting.Wait(1500)) { return $false }
        return $client.Connected
    } catch { return $false }
    finally { $client.Dispose() }
}

function Read-GeoQaResult {
    while ($true) {
        $answer = (Read-Host 'Sikerult? [i=igen, n=nem, k=kihagyas, q=kilepes]').Trim().ToLowerInvariant()
        switch ($answer) {
            'i' { return 'PASS' }
            'n' { return 'FAIL' }
            'k' { return 'SKIP' }
            'q' { throw (New-Object OperationCanceledException('A felhasznalo megszakitotta a probat.')) }
            default { Write-Host 'i, n, k vagy q erteket adj meg.' }
        }
    }
}

function Read-GeoQaReady([string]$Message) {
    Write-Host $Message -ForegroundColor Yellow
    while ($true) {
        $answer = (Read-Host 'A helyi mentes befejezodott, folytathato? [i/k/q]').Trim().ToLowerInvariant()
        switch ($answer) {
            'i' { return $true }
            'k' { return $false }
            'q' { throw (New-Object OperationCanceledException('A felhasznalo megszakitotta a probat.')) }
            default { Write-Host 'i, k vagy q erteket adj meg.' }
        }
    }
}

function Invoke-GeoQaAdb([string]$Adb, [string]$Serial, [string[]]$Arguments) {
    $output = @(& $Adb -s $Serial @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('Az adb parancs sikertelen: ' + ($Arguments -join ' ')) }
    return $output
}

function Restart-GeoQaApp([string]$Adb, [string]$Serial, [string]$Package, [string]$Component) {
    [void](Invoke-GeoQaAdb $Adb $Serial @('shell', 'am', 'force-stop', $Package))
    [void](Invoke-GeoQaAdb $Adb $Serial @('shell', 'am', 'start', '-W', '-n', $Component))
}

function Invoke-GeoPhoneCheck([string]$RequestedDevice, [string]$RequestedPackage) {
    $root = [IO.Path]::GetFullPath($PSScriptRoot)
    $launcher = Join-Path $root 'geocapture_android.ps1'
    if (-not (Test-Path -LiteralPath (Join-Path $root 'pubspec.yaml') -PathType Leaf) -or
            -not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw 'A fajlokat a Flutter-projekt gyokerebe masold, a pubspec.yaml es a geocapture_android.ps1 melle.'
    }
    . $launcher -DeviceId $RequestedDevice
    $adb = Find-GeoAdb $root
    $allLines = @(& $adb devices -l)
    if ($LASTEXITCODE -ne 0) { throw 'Az Android-eszkozok keresese sikertelen.' }
    $devices = @(ConvertFrom-GeoAdbDevices $allLines | Where-Object { $_.State -eq 'device' })
    if ($devices.Count -eq 0) { throw 'Nincs engedelyezett Android-eszkoz. Oldd fel a telefont es ellenorizd az USB debugging kapcsolatot.' }
    if (-not [string]::IsNullOrWhiteSpace($RequestedDevice)) {
        $selected = @($devices | Where-Object { $_.Id -ceq $RequestedDevice })
        if ($selected.Count -ne 1) { throw 'A megadott eszkoz nem elerheto.' }
        $device = $selected[0]
    } elseif ($devices.Count -eq 1) { $device = $devices[0] }
    else {
        for ($i = 0; $i -lt $devices.Count; $i++) { Write-Host ('{0}. {1} {2}' -f ($i + 1), $devices[$i].Id, $devices[$i].Description) }
        $choice = 0
        $answer = Read-Host 'Melyik eszkoz? Add meg a sorszamat'
        if (-not [int]::TryParse($answer, [ref]$choice) -or $choice -lt 1 -or $choice -gt $devices.Count) { throw 'Ervenytelen eszkozvalasztas.' }
        $device = $devices[$choice - 1]
    }

    $package = $RequestedPackage
    if ([string]::IsNullOrWhiteSpace($package)) {
        foreach ($name in @('android\app\build.gradle.kts', 'android\app\build.gradle')) {
            $path = Join-Path $root $name
            if (Test-Path -LiteralPath $path -PathType Leaf) { $package = Get-GeoQaApplicationId ([IO.File]::ReadAllText($path)); if ($package) { break } }
        }
    }
    if ([string]::IsNullOrWhiteSpace($package)) { $package = Read-Host 'Az alkalmazas applicationId erteke' }
    if (-not (Test-GeoQaApplicationId $package)) { throw 'Ervenytelen applicationId.' }

    $settingsFile = Join-Path $root '.dart_tool\geocapture\android.debug.json'
    if (-not (Test-Path -LiteralPath $settingsFile -PathType Leaf)) { throw 'Elobb inditsd egyszer az alkalmazast a GeoCapture_Android.bat fajllal.' }
    $settings = [IO.File]::ReadAllText($settingsFile) | ConvertFrom-Json
    if ($settings.API_BASE_URL -cne 'https://localhost:7043') { throw 'Ez a proba a helyi USB-s https://localhost:7043 API-cimet hasznalja.' }
    $pem = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($settings.DEV_HTTPS_CERT_BASE64))
    [void](New-GeoAndroidDefines $pem)
    $der = [Convert]::FromBase64String(($pem -replace '-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s', ''))
    $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$der)
    try {
        $apiThumbprint = $certificate.Thumbprint
        Assert-GeoApiHealth 'https://localhost:7043/health' $certificate.Thumbprint
        Assert-GeoApiHealth 'https://localhost:7043/health/database' $certificate.Thumbprint
    } finally { $certificate.Dispose() }

    $component = Get-GeoQaLauncher @(Invoke-GeoQaAdb $adb $device.Id @('shell', 'cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER', $package)) $package
    if (-not $component) { throw 'A telepitett alkalmazas inditoja nem talalhato. Inditsd elobb a GeoCapture_Android.bat fajlt; egyedi applicationIdSuffix eseten add meg a teljes csomagnevet -ApplicationId parameterrel.' }
    $mapping = @(Invoke-GeoQaAdb $adb $device.Id @('reverse', '--list'))
    foreach ($line in $mapping) {
        if ($line -match '\stcp:7043\s+(\S+)' -and $Matches[1] -ne 'tcp:7043') { throw 'A 7043-as USB-port mas celra van tovabbitva. Ellenorizd a meglevo portbeallitast.' }
    }
    [void](Invoke-GeoQaAdb $adb $device.Id @('reverse', 'tcp:7043', 'tcp:7043'))
    $model = (@(Invoke-GeoQaAdb $adb $device.Id @('shell', 'getprop', 'ro.product.model')) -join ' ').Trim()
    $reportPath = Join-Path $root ('.dart_tool\geocapture\phone_checks\{0}-{1}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([Guid]::NewGuid().ToString('N').Substring(0, 8)))
    $cases = @(Get-GeoQaCases)
    $results = [ordered]@{}
    $runtimeError = ''
    try {
        [void](Invoke-GeoQaAdb $adb $device.Id @('shell', 'am', 'start', '-W', '-n', $component))
        Write-Host 'A teszt vegigvezeti a telefonos proban. Az i valasz jelenti a sikeres ellenorzest. A kihagyott lepes nem szamit sikernek.' -ForegroundColor Cyan
        Write-Host 'Kulon probafiokkal es probafotokkal dolgozz: lesz helyi fototorles es uj, a szerveren megmarado probafeltoltes.' -ForegroundColor Yellow
        Write-Host ('Telefon: ' + $model)
        foreach ($case in $cases) {
            Write-Host ('Proba: ' + $case.Title) -ForegroundColor Cyan
            if ($case.Action -ne 'none' -and -not (Read-GeoQaReady $case.Prepare)) {
                $results[$case.Id] = 'SKIP'
            } else {
                if ($case.Id -eq 'resume') {
                    Assert-GeoApiHealth 'https://localhost:7043/health' $apiThumbprint
                    Assert-GeoApiHealth 'https://localhost:7043/health/database' $apiThumbprint
                }
                if ($case.Action -eq 'restart') { Restart-GeoQaApp $adb $device.Id $package $component }
                Write-Host $case.Verify
                if ($case.Action -eq 'offline') {
                    if (Test-GeoQaTcpAvailable) { throw 'A backend meg fut. A halozati hibaprobahoz elobb Ctrl+C-vel allitsd le annak SAJAT konzolablakaban, es futtasd ujra a probat.' }
                    $results[$case.Id] = Invoke-GeoQaNetworkPause `
                        { [void](Invoke-GeoQaAdb $adb $device.Id @('reverse', '--remove', 'tcp:7043')) } `
                        { Read-GeoQaResult } `
                        { [void](Invoke-GeoQaAdb $adb $device.Id @('reverse', 'tcp:7043', 'tcp:7043')) }
                } else { $results[$case.Id] = Read-GeoQaResult }
            }
            Write-GeoQaReport $reportPath $cases $results $model $package $runtimeError
        }
    } catch {
        $runtimeError = $_.Exception.Message
        Write-Host ('A proba megszakadt: ' + $runtimeError) -ForegroundColor Red
    } finally {
        try { [void](Invoke-GeoQaAdb $adb $device.Id @('reverse', 'tcp:7043', 'tcp:7043')) }
        catch { $runtimeError = $runtimeError + ' Az USB-port helyreallitasa sikertelen; inditsd ujra a GeoCapture_Android.bat fajlt.' }
        Write-GeoQaReport $reportPath $cases $results $model $package $runtimeError
        Write-Host ('Jegyzokonyv: ' + $reportPath) -ForegroundColor Cyan
        Write-Host 'Ha a halozati probanal leallitottad a backendet, inditsd ujra a korabbi inditasoddal.' -ForegroundColor Yellow
    }
    $summary = Get-GeoQaSummary $cases $results $runtimeError
    Write-Host ('Eredmeny: ' + $summary.State)
    if ($summary.State -eq 'PASSED') { return 0 }
    if ($summary.State -eq 'INCOMPLETE') { return 2 }
    return 1
}

if ($MyInvocation.InvocationName -eq '.') { return }
try { exit (Invoke-GeoPhoneCheck $DeviceId $ApplicationId) }
catch { Write-Host ('HIBA: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }