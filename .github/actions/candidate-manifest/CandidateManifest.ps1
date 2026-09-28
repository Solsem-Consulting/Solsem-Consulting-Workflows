[CmdletBinding()]
param(
    [string]$Path = $env:CANDIDATE_PATH,
    [string]$ExpectedManifest = $env:EXPECTED_MANIFEST,
    [string]$ExpectedDigest = $env:EXPECTED_DIGEST
)

# Hashes a release candidate directory into a sha256sum-style manifest and, when an
# approved manifest is supplied, fails unless the directory matches it exactly.
# Manifest format: "<sha256>  <relative/path>" per file, sorted ordinally by path,
# LF line endings with a trailing LF. The digest is the SHA-256 of that UTF-8 text.

$ErrorActionPreference = 'Stop'

function Get-TextDigest {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function ConvertTo-NormalizedManifest {
    param([AllowEmptyString()][string]$Manifest)

    $lines = @(($Manifest -replace "`r", '') -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($line in $lines) {
        if ($line -notmatch '^[0-9a-f]{64}  \S') {
            throw "Invalid manifest line: $line"
        }
    }
    if ($lines.Count -eq 0) {
        return ''
    }
    return ($lines -join "`n") + "`n"
}

function Get-CandidateManifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Release candidate directory not found: $Path"
    }

    $root = (Resolve-Path -LiteralPath $Path).Path
    $entries = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $relativePath = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $entries.Add("$hash  $relativePath")
    }
    if ($entries.Count -eq 0) {
        throw "Release candidate directory contains no files: $Path"
    }

    $sorted = [string[]]$entries.ToArray()
    [Array]::Sort($sorted, [Comparison[string]] { param($a, $b) [string]::CompareOrdinal($a.Substring(66), $b.Substring(66)) })
    return ($sorted -join "`n") + "`n"
}

function Compare-CandidateManifest {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Expected,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Actual
    )

    $toMap = {
        param([string]$Manifest)
        $map = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
        foreach ($line in ($Manifest -split "`n" | Where-Object { $_ })) {
            $map[$line.Substring(66)] = $line.Substring(0, 64)
        }
        return , $map
    }
    $expectedFiles = & $toMap $Expected
    $actualFiles = & $toMap $Actual

    $differences = [Collections.Generic.List[string]]::new()
    foreach ($file in $expectedFiles.Keys) {
        if (-not $actualFiles.ContainsKey($file)) {
            $differences.Add("missing: $file")
        }
        elseif ($actualFiles[$file] -ne $expectedFiles[$file]) {
            $differences.Add("changed: $file (approved $($expectedFiles[$file]), found $($actualFiles[$file]))")
        }
    }
    foreach ($file in $actualFiles.Keys) {
        if (-not $expectedFiles.ContainsKey($file)) {
            $differences.Add("unexpected: $file")
        }
    }
    return , $differences.ToArray()
}

function Write-ActionOutput {
    param([string]$Name, [string]$Value)

    if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        return
    }
    $delimiter = "EOF_$([guid]::NewGuid().ToString('N'))"
    @("$Name<<$delimiter", $Value.TrimEnd("`n"), $delimiter) |
        Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

function Invoke-CandidateManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$ExpectedManifest,
        [AllowEmptyString()][string]$ExpectedDigest
    )

    $manifest = Get-CandidateManifest -Path $Path
    $digest = Get-TextDigest -Text $manifest
    $fileCount = @($manifest -split "`n" | Where-Object { $_ }).Count

    if (-not [string]::IsNullOrWhiteSpace($ExpectedManifest)) {
        $expected = ConvertTo-NormalizedManifest -Manifest $ExpectedManifest
        $expectedDigestOfText = Get-TextDigest -Text $expected
        if (-not [string]::IsNullOrWhiteSpace($ExpectedDigest) -and $ExpectedDigest.Trim().ToLowerInvariant() -ne $expectedDigestOfText) {
            throw "Approved manifest digest mismatch: expected $($ExpectedDigest.Trim()), approved manifest text hashes to $expectedDigestOfText."
        }

        $differences = Compare-CandidateManifest -Expected $expected -Actual $manifest
        if ($differences.Count -gt 0) {
            $differences | ForEach-Object { Write-Host "::error title=Release candidate mismatch::$_" }
            throw "Release candidate does not match the approved manifest ($($differences.Count) difference(s))."
        }
        Write-Host "Release candidate matches the approved manifest: $fileCount file(s), digest $digest."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ExpectedDigest)) {
        throw 'expected-digest requires expected-manifest.'
    }
    else {
        Write-Host "Hashed release candidate: $fileCount file(s), digest $digest."
    }

    Write-Host $manifest.TrimEnd("`n")
    Write-ActionOutput -Name 'manifest' -Value $manifest
    Write-ActionOutput -Name 'digest' -Value $digest
    Write-ActionOutput -Name 'file-count' -Value ([string]$fileCount)

    return [pscustomobject]@{ Manifest = $manifest; Digest = $digest; FileCount = $fileCount }
}

if ($MyInvocation.InvocationName -ne '.') {
    $null = Invoke-CandidateManifest -Path $Path -ExpectedManifest $ExpectedManifest -ExpectedDigest $ExpectedDigest
}
