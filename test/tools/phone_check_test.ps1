#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\geocapture_phone_check.ps1')

$passed = 0
function Assert-GeoQa($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw ("FAIL: $Message - expected: $Expected; actual: $Actual") }
    $script:passed++
    Write-Host ('PASS: ' + $Message) -ForegroundColor Green
}

Assert-GeoQa (Get-GeoQaApplicationId 'applicationId = "com.example.geo_capture"') 'com.example.geo_capture' 'Reads Kotlin DSL applicationId'
Assert-GeoQa (Get-GeoQaApplicationId "applicationId 'ro.example.capture'") 'ro.example.capture' 'Reads Groovy applicationId'
Assert-GeoQa (Get-GeoQaApplicationId 'applicationId = "ro.example.capture" // note') 'ro.example.capture' 'Accepts a trailing Gradle comment'
Assert-GeoQa (Get-GeoQaApplicationId 'namespace = "com.example.other"') $null 'Does not guess applicationId from namespace'
Assert-GeoQa (Get-GeoQaApplicationId 'applicationId = project.property("appId")') $null 'Requires input when Gradle computes the applicationId'
Assert-GeoQa (Test-GeoQaApplicationId 'com.example.geo_capture') $true 'Accepts the current package name'
Assert-GeoQa (Test-GeoQaApplicationId 'com.example;reboot') $false 'Rejects shell syntax in a package name'
Assert-GeoQa (Test-GeoQaApplicationId '') $false 'Rejects an empty package name'
Assert-GeoQa (Get-GeoQaLauncher @('warning', 'com.example.geo_capture/.MainActivity') 'com.example.geo_capture') 'com.example.geo_capture/.MainActivity' 'Finds the installed launcher component'
Assert-GeoQa (Get-GeoQaLauncher @('com.other.app/.MainActivity') 'com.example.geo_capture') $null 'Rejects another packages component'
Assert-GeoQa (Get-GeoQaLauncher @('No activity found') 'com.example.geo_capture') $null 'Does not invent a missing launcher'

$cases = @(Get-GeoQaCases)
Assert-GeoQa $cases.Count 9 'Provides nine device checks'
Assert-GeoQa (@($cases.Id | Select-Object -Unique).Count) 9 'Device case identifiers are unique'
Assert-GeoQa (@($cases | Where-Object { $_.Action -eq 'offline' }).Count) 1 'Only the intended step disconnects the API'

$results = [ordered]@{}
foreach ($case in $cases) { $results[$case.Id] = 'PASS' }
Assert-GeoQa (Get-GeoQaSummary $cases $results '').State 'PASSED' 'All explicit passes produce PASSED'
$results['camera'] = 'FAIL'
Assert-GeoQa (Get-GeoQaSummary $cases $results '').State 'FAILED' 'A failed check cannot produce PASSED'
$results['camera'] = 'SKIP'
Assert-GeoQa (Get-GeoQaSummary $cases $results '').State 'INCOMPLETE' 'Skipped checks are not passes'
$results.Remove('camera')
Assert-GeoQa (Get-GeoQaSummary $cases $results '').Pending 1 'Unanswered checks remain NOT_RUN'
Assert-GeoQa (Get-GeoQaSummary $cases $results '').State 'INCOMPLETE' 'An unfinished run cannot produce PASSED'
$results['camera'] = 'PASS'
Assert-GeoQa (Get-GeoQaSummary $cases $results 'test interrupted').State 'ABORTED' 'Runtime errors override a complete set of answers'

$calls = New-Object 'Collections.Generic.List[string]'
$result = Invoke-GeoQaNetworkPause { $calls.Add('down') } { $calls.Add('verify'); 'PASS' } { $calls.Add('up') }
Assert-GeoQa $result 'PASS' 'Network verification returns the user supplied result'
Assert-GeoQa ($calls -join ',') 'down,verify,up' 'Connection is restored after a normal check'
$calls.Clear()
$thrown = $false
try { Invoke-GeoQaNetworkPause { $calls.Add('down') } { throw 'simulated interruption' } { $calls.Add('up') } }
catch { $thrown = $true }
Assert-GeoQa $thrown $true 'Interrupted checks retain their error'
Assert-GeoQa ($calls -join ',') 'down,up' 'Connection is restored after an interrupted check'

$listener = New-Object Net.Sockets.TcpListener -ArgumentList @([Net.IPAddress]::Loopback, 0)
try {
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    Assert-GeoQa (Test-GeoQaTcpAvailable '127.0.0.1' $port) $true 'Detects an active local API listener'
}
finally { $listener.Stop() }
Assert-GeoQa (Test-GeoQaTcpAvailable '127.0.0.1' $port) $false 'Detects that the local API listener stopped'

$folder = Join-Path ([IO.Path]::GetTempPath()) ('geo-phone-check-test-' + [Guid]::NewGuid().ToString('N'))
try {
    $path = Join-Path $folder 'report.md'
    $results.Remove('restart')
    Write-GeoQaReport $path $cases $results 'SM S928B' 'com.example.geo_capture' ''
    $content = [IO.File]::ReadAllText($path)
    Assert-GeoQa ($content.Contains('Allapot: INCOMPLETE')) $true 'Report preserves incomplete status'
    Assert-GeoQa ($content.Contains('| Piszkozatok ujrainditas utan | NOT_RUN |')) $true 'Report does not turn unanswered checks into passes'
    Assert-GeoQa ($content.Contains('a telefont hasznalo szemely jelolte')) $true 'Report labels device results as user verified'
}
finally { if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force } }

Write-Host ('Phone-check helper tests passed: ' + $passed) -ForegroundColor Green