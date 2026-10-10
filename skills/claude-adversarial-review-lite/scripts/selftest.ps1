[CmdletBinding()]
param([switch]$LiveProbe)
$ErrorActionPreference = "Stop"
$arguments = @((Join-Path $PSScriptRoot "review_runner.py"), "selftest", "--backend", "claude")
if ($LiveProbe) { $arguments += "--live-probe" }
& python @arguments
exit $LASTEXITCODE
