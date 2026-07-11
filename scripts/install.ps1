param([string]$SkillsRoot = "$env:USERPROFILE\.codex\skills")
$ErrorActionPreference = "Stop"
$name = "claude-adversarial-review-lite"
$source = Join-Path (Split-Path -Parent $PSScriptRoot) "skills\$name"
$dest = Join-Path $SkillsRoot $name
if (-not (Test-Path (Join-Path $source "SKILL.md"))) { throw "Incomplete checkout: SKILL.md not found." }
if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Path (Join-Path $source "*") -Destination $dest -Recurse -Force
Write-Host "Installed $name to $dest"
Write-Host "Restart Codex, then invoke: Use `$claude-adversarial-review-lite to audit this change."

