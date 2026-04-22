$files = @(
    'eshopweb/docker-compose.yml',
    'eshopweb/entrypoint.sh',
    'IMPLEMENTATION.md',
    'medplum/docker-compose.yml',
    'medplum/entrypoint.sh',
    'medplum/medplum.config.json',
    'QUICKSTART.md',
    'README.md',
    'scripts/collect-results.sh',
    'scripts/run-sandbox.sh',
    'scripts/sandbox-reset.sh',
    'VALIDATION.md'
)

Write-Host "=== LOCAL FILE CHECKSUMS ==="
foreach ($file in $files) {
    if (Test-Path $file) {
        $hash = (Get-FileHash $file -Algorithm SHA256).Hash
        Write-Host "$file`n$hash`n"
    } else {
        Write-Host "MISSING: $file`n"
    }
}
