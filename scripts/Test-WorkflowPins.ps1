[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$githubPath = Join-Path $RepositoryRoot '.github'
$workflowFiles = Get-ChildItem -Path $githubPath -Recurse -File |
    Where-Object { $_.Extension -in '.yml', '.yaml' }
$errors = [System.Collections.Generic.List[string]]::new()

foreach ($file in $workflowFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNumber++
        if ($line -notmatch '^\s*(?:-\s*)?uses:\s*(?<reference>[^\s#]+)(?:\s+#\s*(?<version>.*))?$') {
            continue
        }

        $reference = $Matches.reference
        $version = $Matches.version
        if ($reference.StartsWith('./') -or $reference.StartsWith('docker://')) {
            continue
        }

        $relativePath = [IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName)
        if ($reference -notmatch '@[0-9a-fA-F]{40}$') {
            $errors.Add("${relativePath}:${lineNumber}: remote uses reference must use a full commit SHA: $reference")
            continue
        }

        if ([string]::IsNullOrWhiteSpace($version)) {
            $errors.Add("${relativePath}:${lineNumber}: pinned reference must include an upstream version comment")
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Workflow pin policy failed with $($errors.Count) violation(s)."
}

Write-Host "Workflow pin policy passed for $($workflowFiles.Count) YAML file(s)."
