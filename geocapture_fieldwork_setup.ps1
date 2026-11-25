#requires -Version 5.1
[CmdletBinding()]
param([string]$ProjectRoot = $PSScriptRoot, [switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GeoFieldworkAndroidPlan([string]$Root) {
    $settings = Join-Path $Root 'android/settings.gradle.kts'
    $wrapper = Join-Path $Root 'android/gradle/wrapper/gradle-wrapper.properties'
    $app = Join-Path $Root 'android/app/build.gradle.kts'
    foreach ($file in @($settings, $wrapper, $app)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw ('Hianyzik az Android Kotlin DSL fajl: ' + $file)
        }
    }
    $plan = New-Object 'Collections.Generic.List[object]'
    $old = [IO.File]::ReadAllText($settings)
    $new = $old
    foreach ($package in @(@('com.android.application', '8.12.1'), @('org.jetbrains.kotlin.android', '2.2.0'))) {
        $minimum = [Version]$package[1]
        $pattern = '(?<prefix>id\(\s*"' + $package[0] + '"\s*\)\s*version\s*")(?<version>\d+\.\d+\.\d+)(?<suffix>")'
        $new = [regex]::Replace($new, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match)
            if ([Version]$match.Groups['version'].Value -ge $minimum) { return $match.Value }
            return $match.Groups['prefix'].Value + $minimum.ToString() + $match.Groups['suffix'].Value
        })
    }
    if ($new -cne $old) { $plan.Add([pscustomobject]@{ Path = $settings; Old = $old; New = $new }) }
    $old = [IO.File]::ReadAllText($wrapper)
    $new = [regex]::Replace($old, 'gradle-(?<version>\d+(?:\.\d+){1,2})(?<suffix>-(?:all|bin)\.zip)',
        [Text.RegularExpressions.MatchEvaluator]{ param($match)
            if ([Version]$match.Groups['version'].Value -ge [Version]'8.13') { return $match.Value }
            return 'gradle-8.13' + $match.Groups['suffix'].Value
        })
    if ($new -cne $old -and $old -match '(?m)^distributionSha256Sum=') {
        # Official Gradle 8.13 release checksums: preserve verification when upgrading.
        $checksum = if ($new.Contains('gradle-8.13-all.zip')) {
            'fba8464465835e74f7270bbf43d6d8a8d7709ab0a43ce1aa3323f73e9aa0c612'
        } else { '20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78' }
        $new = [regex]::Replace($new, '(?m)^distributionSha256Sum=[^\r\n]*', ('distributionSha256Sum=' + $checksum))
    }
    if ($new -cne $old) { $plan.Add([pscustomobject]@{ Path = $wrapper; Old = $old; New = $new }) }
    $old = [IO.File]::ReadAllText($app)
    $new = [regex]::Replace($old, '(?m)^(?<indent>[ \t]*)(?<name>compileSdk|minSdk)[ \t]*=[ \t]*(?<value>[^\r\n]+)',
        [Text.RegularExpressions.MatchEvaluator]{ param($match)
            $name = $match.Groups['name'].Value
            $minimum = if ($name -eq 'compileSdk') { 36 } else { 24 }
            $value = $match.Groups['value'].Value.Trim()
            $expression = ($value -split '//', 2)[0].Trim()
            $comment = if ($value.Contains('//')) { ' //' + ($value -split '//', 2)[1] } else { '' }
            if ($expression -match '^\d+$' -and [int]$expression -ge $minimum) { return $match.Value }
            if ($expression -match ('^maxOf\(\s*' + $minimum + '\s*,')) { return $match.Value }
            return $match.Groups['indent'].Value + $name + ' = maxOf(' + $minimum + ', ' + $expression + ')' + $comment
        })
    if ($new -cne $old) { $plan.Add([pscustomobject]@{ Path = $app; Old = $old; New = $new }) }
    return $plan.ToArray()
}

function Write-GeoFieldworkAndroidPlan([object[]]$Plan) {
    # Validate the complete plan before touching any file.
    foreach ($item in $Plan) {
        if ([IO.File]::ReadAllText($item.Path) -cne $item.Old) { throw 'A konfiguracio kozben megvaltozott. Inditsd ujra az ellenorzest.' }
    }
    foreach ($item in $Plan) {
        $backup = $item.Path + '.before-fieldwork'
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { [IO.File]::WriteAllText($backup, $item.Old) }
        [IO.File]::WriteAllText($item.Path, $item.New, (New-Object Text.UTF8Encoding($false)))
        Write-Host ('Frissitve: ' + $item.Path)
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
try {
    $plan = @(Get-GeoFieldworkAndroidPlan ([IO.Path]::GetFullPath($ProjectRoot)))
    if ($Apply) { Write-GeoFieldworkAndroidPlan $plan }
    elseif ($plan.Count -gt 0) { foreach ($item in $plan) { Write-Host ('Frissitendo: ' + $item.Path) } }
    Write-Host 'QR-modul: Android API 36 SDK, Java 17 vagy ujabb, es minSdk 24 vagy ujabb szukseges.'
    Write-Host 'Az ujabb Gradle/AGP/Kotlin verziok megmaradnak; a fajlokrol .before-fieldwork masolat keszul.'
    exit 0
}
catch { Write-Host ('HIBA: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }