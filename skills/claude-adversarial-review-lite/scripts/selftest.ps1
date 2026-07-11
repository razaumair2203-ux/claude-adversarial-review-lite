[CmdletBinding()]
param(
  [switch]$LiveProbe
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillDir = Split-Path -Parent $ScriptDir
$RepoRoot = Split-Path -Parent (Split-Path -Parent $SkillDir)
$Runner = Join-Path $ScriptDir "invoke-claude-review.ps1"

function Add-Check($Name, $Status, $Detail) {
  [pscustomobject]@{ name=$Name; status=$Status; detail=$Detail }
}

function Resolve-ClaudeCommand {
  foreach ($candidate in @($env:CLAUDE_REVIEW_CLI, $env:CLAUDE_BIN)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  $pathCommand = Get-Command claude -ErrorAction SilentlyContinue
  if ($pathCommand) { return $pathCommand.Source }
  $userHome = [Environment]::GetFolderPath("UserProfile")
  foreach ($candidate in @((Join-Path $userHome ".local\bin\claude.exe"), (Join-Path $userHome "AppData\Local\Programs\claude\claude.exe"))) {
    if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  $extensionRoots = @((Join-Path $userHome ".vscode\extensions"))
  $usersRoot = Split-Path -Parent $userHome
  if (Test-Path -LiteralPath $usersRoot) {
    $extensionRoots += Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue |
      ForEach-Object { Join-Path $_.FullName ".vscode\extensions" }
  }
  foreach ($extensions in ($extensionRoots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $extensions)) { continue }
    $bundled = Get-ChildItem -LiteralPath $extensions -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "anthropic.claude-code-*" -and $_.Name -like "*-win32-x64" } |
      Sort-Object Name -Descending |
      ForEach-Object { Join-Path $_.FullName "resources\native-binary\claude.exe" } |
      Where-Object { Test-Path -LiteralPath $_ } |
      Select-Object -First 1
    if ($bundled) { return (Resolve-Path -LiteralPath $bundled).Path }
  }
  return $null
}

$checks = New-Object System.Collections.Generic.List[object]
$git = Get-Command git -ErrorAction SilentlyContinue
$checks.Add((Add-Check "git" ($(if ($git) { "pass" } else { "fail" })) ($(if ($git) { (& git --version) } else { "Git is not available." }))))
$claude = Resolve-ClaudeCommand
if ($claude) {
  $checks.Add((Add-Check "claude_cli" "pass" $claude))
  $checks.Add((Add-Check "claude_version" "pass" ((& $claude --version 2>&1) -join "`n")))
  $auth = (& $claude auth status 2>&1) -join "`n"
  if ($LASTEXITCODE -eq 0 -and $auth -match '"loggedIn"\s*:\s*true') {
    $checks.Add((Add-Check "claude_auth" "pass" "loggedIn=true"))
  } else {
    $checks.Add((Add-Check "claude_auth" "fail" ($auth.Trim())))
  }
} else {
  $checks.Add((Add-Check "claude_cli" "fail" "Set CLAUDE_REVIEW_CLI/CLAUDE_BIN or install/authenticate Claude Code CLI."))
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ("claude-review-selftest-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  $probe = Join-Path $temp "write-probe.txt"
  "ok" | Set-Content -LiteralPath $probe
  $checks.Add((Add-Check "temp_write" "pass" $temp))

  $stress = Join-Path $RepoRoot "tests\stress.ps1"
  if (Test-Path -LiteralPath $stress) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stress | Out-Null
    $checks.Add((Add-Check "mock_stress" ($(if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) { "pass" } else { "fail" })) "PowerShell stress suite"))
  } else {
    $checks.Add((Add-Check "mock_stress" "fail" "tests/stress.ps1 missing"))
  }

  if ($LiveProbe -and $claude) {
    $bundle = Join-Path $temp "synthetic-bundle.md"
    $result = Join-Path $temp "synthetic-result.json"
    @"
# Synthetic self-test bundle

No repository content is included. Return an approved review if the transport works.
"@ | Set-Content -LiteralPath $bundle
    $env:CLAUDE_REVIEW_CLI = $claude
    & $Runner -BundlePath $bundle -ResultPath $result -TimeoutSeconds 120 -MaxTurns 2
    $parsed = Get-Content -Raw -LiteralPath $result | ConvertFrom-Json
    $checks.Add((Add-Check "live_probe" ($(if ($LASTEXITCODE -eq 0 -and $parsed.result -eq "success") { "pass" } else { "fail" })) ($parsed.result + ": " + $parsed.errors)))
  }
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

$overall = if ($checks | Where-Object { $_.status -eq "fail" }) { "fail" } else { "pass" }
[pscustomobject]@{ result=$overall; checks=$checks } | ConvertTo-Json -Depth 6
if ($overall -ne "pass") { exit 2 }
