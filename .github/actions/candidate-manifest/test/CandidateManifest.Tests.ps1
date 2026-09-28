$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' 'CandidateManifest.ps1')

function Assert-Throws {
    param([scriptblock]$Script, [string]$Pattern, [string]$Because)

    try {
        # Expected failures print ::error annotations; keep them out of a passing CI log.
        & $Script 6>$null
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "$Because - unexpected error: $($_.Exception.Message)"
        }
        return
    }
    throw "$Because - expected an error matching '$Pattern'."
}

function New-Candidate {
    $root = Join-Path ([IO.Path]::GetTempPath()) "candidate-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path (Join-Path $root 'installer' 'nb-NO') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'App-1.0.0.zip') -Value 'zip' -NoNewline
    Set-Content -LiteralPath (Join-Path $root 'installer' 'nb-NO' 'Søknad oppsett.msi') -Value 'msi' -NoNewline
    Set-Content -LiteralPath (Join-Path $root 'B.txt') -Value 'b' -NoNewline
    return $root
}

$candidate = New-Candidate
$outputFile = New-TemporaryFile
try {
    $env:GITHUB_OUTPUT = $outputFile.FullName
    $result = Invoke-CandidateManifest -Path $candidate -ExpectedManifest '' -ExpectedDigest ''
    Remove-Item Env:GITHUB_OUTPUT

    $lines = @($result.Manifest -split "`n" | Where-Object { $_ })
    $paths = @($lines | ForEach-Object { $_.Substring(66) })
    if (($paths -join '|') -ne 'App-1.0.0.zip|B.txt|installer/nb-NO/Søknad oppsett.msi') {
        throw "Manifest must list relative forward-slash paths in ordinal order, got: $($paths -join '|')"
    }
    $zipHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('zip'))).ToLowerInvariant()
    if ($lines[0] -ne "$zipHash  App-1.0.0.zip") {
        throw "Manifest lines must use sha256sum format, got: $($lines[0])"
    }
    if (-not $result.Manifest.EndsWith("`n") -or $result.Manifest.Contains("`r")) {
        throw 'Manifest must use LF line endings with a trailing LF.'
    }
    if ($result.Digest -ne (Get-TextDigest -Text $result.Manifest) -or $result.FileCount -ne 3) {
        throw 'Digest must be the SHA-256 of the manifest text, and the file count must match.'
    }
    $outputs = Get-Content -LiteralPath $outputFile.FullName -Raw
    if ($outputs -notmatch "(?s)manifest<<(EOF_[0-9a-f]{32})\r?\n[0-9a-f]{64}  App-1\.0\.0\.zip\r?\n.*?\r?\n\1" -or
        $outputs -notmatch "digest<<(EOF_[0-9a-f]{32})\r?\n$($result.Digest)\r?\n\1") {
        throw "Action outputs must be written as multiline GITHUB_OUTPUT values, got: $outputs"
    }

    # A manifest that passed through workflow outputs may gain CRLF or lose its trailing newline.
    $transported = $result.Manifest.TrimEnd("`n").Replace("`n", "`r`n")
    $verified = Invoke-CandidateManifest -Path $candidate -ExpectedManifest $transported -ExpectedDigest $result.Digest
    if ($verified.Digest -ne $result.Digest) {
        throw 'An unchanged candidate must verify against its own manifest.'
    }

    Assert-Throws { Invoke-CandidateManifest -Path $candidate -ExpectedManifest $result.Manifest -ExpectedDigest ('0' * 64) } 'digest mismatch' 'A manifest that does not match the approved digest must be rejected'
    Assert-Throws { Invoke-CandidateManifest -Path $candidate -ExpectedManifest '' -ExpectedDigest $result.Digest } 'requires expected-manifest' 'A digest without a manifest must be rejected'
    Assert-Throws { Invoke-CandidateManifest -Path $candidate -ExpectedManifest 'not a manifest' -ExpectedDigest '' } 'Invalid manifest line' 'A malformed manifest must be rejected'

    Set-Content -LiteralPath (Join-Path $candidate 'B.txt') -Value 'rebuilt' -NoNewline
    Assert-Throws { Invoke-CandidateManifest -Path $candidate -ExpectedManifest $result.Manifest -ExpectedDigest '' } 'does not match the approved manifest' 'A changed file must be rejected'

    Set-Content -LiteralPath (Join-Path $candidate 'B.txt') -Value 'b' -NoNewline
    Set-Content -LiteralPath (Join-Path $candidate 'extra.dll') -Value 'x' -NoNewline
    Assert-Throws { Invoke-CandidateManifest -Path $candidate -ExpectedManifest $result.Manifest -ExpectedDigest '' } 'does not match the approved manifest' 'An unexpected file must be rejected'

    Remove-Item -LiteralPath (Join-Path $candidate 'extra.dll')
    Remove-Item -LiteralPath (Join-Path $candidate 'App-1.0.0.zip')
    $differences = Compare-CandidateManifest -Expected $result.Manifest -Actual (Get-CandidateManifest -Path $candidate)
    if (($differences -join '|') -ne 'missing: App-1.0.0.zip') {
        throw "A missing file must be reported by name, got: $($differences -join '|')"
    }

    $empty = Join-Path ([IO.Path]::GetTempPath()) "candidate-empty-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $empty | Out-Null
    Assert-Throws { Get-CandidateManifest -Path $empty } 'contains no files' 'An empty candidate must be rejected'
    Assert-Throws { Get-CandidateManifest -Path (Join-Path $empty 'missing') } 'not found' 'A missing candidate directory must be rejected'
    Remove-Item -LiteralPath $empty -Recurse -Force
}
finally {
    Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outputFile.FullName -Force -ErrorAction SilentlyContinue
}

Write-Host 'Candidate manifest checks passed.'
