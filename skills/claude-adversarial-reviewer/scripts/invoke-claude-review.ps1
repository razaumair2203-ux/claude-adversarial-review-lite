[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$BundlePath,
  [Parameter(Mandatory)][string]$ResultPath,
  [string]$Model = "",
  [int]$MaxTurns = 8,
  [decimal]$MaxBudgetUsd = 3.00,
  [int]$TimeoutSeconds = 600,
  [Parameter(DontShow)][string]$MockOutputPath = "",
  [Parameter(DontShow)][int]$MockExitCode = 0,
  [Parameter(DontShow)][string]$MockClaudeCommand = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillDir = Split-Path -Parent $ScriptDir
$SchemaPath = Join-Path $SkillDir "references\review-schema.json"
$PromptPath = Join-Path $SkillDir "references\reviewer-prompt.md"

function Resolve-ClaudeCommand {
  foreach ($candidate in @($env:CLAUDE_REVIEW_CLI, $env:CLAUDE_BIN)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  $pathCommand = Get-Command claude -ErrorAction SilentlyContinue
  if ($pathCommand) { return $pathCommand.Source }
  $userHome = [Environment]::GetFolderPath("UserProfile")
  $localCandidates = @(
    (Join-Path $userHome ".local\bin\claude.exe"),
    (Join-Path $userHome "AppData\Local\Programs\claude\claude.exe")
  )
  foreach ($candidate in $localCandidates) {
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

function Write-Envelope($Value) {
  $parent = Split-Path -Parent $ResultPath
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding utf8
}

if (-not (Test-Path -LiteralPath $BundlePath) -or (Get-Item $BundlePath).Length -eq 0) {
  Write-Envelope @{ result="invalid_output"; verdict=$null; review_quality="unknown"; review=$null; errors="Bundle is missing or empty."; session_id=$null }
  exit 2
}
foreach ($required in @($SchemaPath, $PromptPath)) {
  if (-not (Test-Path -LiteralPath $required)) {
    Write-Envelope @{ result="setup_needed"; verdict=$null; review_quality="unknown"; review=$null; errors="Missing skill resource: $required"; session_id=$null }
    exit 2
  }
}
if ($MockClaudeCommand) { $ClaudeCommand = $MockClaudeCommand } elseif (-not $MockOutputPath) { $ClaudeCommand = Resolve-ClaudeCommand }
if (-not $MockOutputPath -and -not $ClaudeCommand) {
  Write-Envelope @{ result="setup_needed"; verdict=$null; review_quality="degraded_environmental"; review=$null; errors="Claude Code CLI is not installed or not on PATH."; session_id=$null }
  exit 2
}

$schema = Get-Content -Raw -LiteralPath $SchemaPath | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 20
# Start-Process joins ArgumentList into one Windows command line. Escape JSON quotes
# so the child process receives the schema as one literal argument.
$schemaArgument = $schema.Replace('"', '\"')
$settings = '{"disableAllHooks":true,"autoMemoryEnabled":false}'
$settingsArgument = $settings.Replace('"', '\"')
$mcpConfigArgument = '{\"mcpServers\":{}}'
$promptArgument = '"' + $PromptPath + '"'
$stdout = [IO.Path]::GetTempFileName()
$stderr = [IO.Path]::GetTempFileName()
$reviewCwd = Join-Path ([IO.Path]::GetTempPath()) ("claude-review-cwd-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $reviewCwd | Out-Null
try {
  $args = @("-p", "--permission-mode", "dontAsk", "--tools=", "--disable-slash-commands", "--setting-sources=", "--strict-mcp-config", "--mcp-config", $mcpConfigArgument, "--settings", $settingsArgument, "--output-format", "json", "--json-schema", $schemaArgument, "--system-prompt-file", $promptArgument, "--max-turns", "$MaxTurns", "--max-budget-usd", "$MaxBudgetUsd", "--no-session-persistence")
  if ($Model) { $args += @("--model", $Model) }
  if ($MockOutputPath -and -not $MockClaudeCommand) {
    Copy-Item -LiteralPath $MockOutputPath -Destination $stdout -Force
    $exitCode = $MockExitCode
  } else {
    $process = Start-Process -FilePath $ClaudeCommand -ArgumentList $args -WorkingDirectory $reviewCwd -RedirectStandardInput $BundlePath -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      try { $process.Kill($true) } catch { $process.Kill() }
      Write-Envelope @{ result="timeout"; verdict=$null; review_quality="degraded_environmental"; review=$null; errors="Claude review exceeded ${TimeoutSeconds}s."; session_id=$null }
      exit 3
    }
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    if ($MockClaudeCommand) { $exitCode = $MockExitCode }
    if ($null -eq $exitCode) {
      try {
        $exitProbe = Get-Content -Raw -LiteralPath $stdout | ConvertFrom-Json
        if ($exitProbe.subtype -eq "success" -and $exitProbe.is_error -eq $false) { $exitCode = 0 } else { $exitCode = 1 }
      } catch { $exitCode = 1 }
    }
  }
  $err = Get-Content -Raw -LiteralPath $stderr -ErrorAction SilentlyContinue
  if ($null -eq $err) { $err = "" } else { $err = $err.Trim() }
  if ($exitCode -ne 0) {
    $stdoutDiagnostic = Get-Content -Raw -LiteralPath $stdout -ErrorAction SilentlyContinue
    if ($null -eq $stdoutDiagnostic) { $stdoutDiagnostic = "" }
    if ($err.Length -gt 1000) { $err = $err.Substring(0,1000) }
    if (-not $err -and $stdoutDiagnostic) {
      $err = $stdoutDiagnostic.Trim()
      if ($err.Length -gt 1000) { $err = $err.Substring(0,1000) }
    }
    $err = "Claude exited with code $exitCode. $err".Trim()
    Write-Envelope @{ result="launch_failure"; verdict=$null; review_quality="degraded_environmental"; review=$null; errors=$err; session_id=$null }
    exit 3
  }
  try { $outer = Get-Content -Raw -LiteralPath $stdout | ConvertFrom-Json } catch {
    Write-Envelope @{ result="invalid_output"; verdict=$null; review_quality="unknown"; review=$null; errors="Claude returned malformed outer JSON."; session_id=$null }
    exit 4
  }
  $review = $outer.structured_output
  if (-not $review -and $outer.result -is [string]) {
    try { $review = $outer.result | ConvertFrom-Json } catch { $review = $null }
  }
  if (-not $review -or -not $review.verdict -or -not $review.review_quality) {
    Write-Envelope @{ result="invalid_output"; verdict=$null; review_quality="unknown"; review=$null; errors="Claude response lacks structured_output or required fields."; session_id=$outer.session_id }
    exit 4
  }
  $count = @($review.findings).Count
  if (($review.verdict -eq "approved" -and $count -ne 0) -or ($review.verdict -eq "revise" -and $count -eq 0)) {
    Write-Envelope @{ result="invalid_output"; verdict=$review.verdict; review_quality=$review.review_quality; review=$review; errors="Verdict and finding count are inconsistent."; session_id=$outer.session_id }
    exit 4
  }
  $rubricFails = @($review.rubric_results | Where-Object { $_.result -eq "FAIL" }).Count
  if ($review.verdict -eq "approved" -and $rubricFails -ne 0) {
    Write-Envelope @{ result="invalid_output"; verdict=$review.verdict; review_quality=$review.review_quality; review=$review; errors="Verdict is approved but the rubric contains FAIL results."; session_id=$outer.session_id }
    exit 4
  }
  Write-Envelope @{ result="success"; verdict=$review.verdict; review_quality=$review.review_quality; review=$review; errors=$null; session_id=$outer.session_id }
} finally {
  Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $reviewCwd -Recurse -Force -ErrorAction SilentlyContinue
}
