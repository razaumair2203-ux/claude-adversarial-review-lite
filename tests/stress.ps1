$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ("claude-review-stress-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$spaceRoot = Join-Path $temp "skill path with space"
Copy-Item -LiteralPath (Join-Path $root "skills\claude-adversarial-reviewer") -Destination $spaceRoot -Recurse
$runner = Join-Path $spaceRoot "scripts\invoke-claude-review.ps1"
$runnerSource = Get-Content -Raw -LiteralPath $runner
if ($runnerSource -notmatch 'mcpServers') { throw "runner must pass a structurally valid empty MCP config" }
try {
  $bundle = Join-Path $temp "bundle.md"
  "# Synthetic bundle`nNo repository content." | Set-Content $bundle
  $cases = @(
    @{ name="approved"; fixture="approved.json"; exit="0"; expected="success"; code=0 },
    @{ name="approved-result-string"; fixture="approved-result-string.json"; exit="0"; expected="success"; code=0 },
    @{ name="revise"; fixture="revise.json"; exit="0"; expected="success"; code=0 },
    @{ name="inconsistent"; fixture="inconsistent.json"; exit="0"; expected="invalid_output"; code=4 },
    @{ name="rubric-fail-approved"; fixture="rubric-fail-approved.json"; exit="0"; expected="invalid_output"; code=4 },
    @{ name="malformed"; fixture="malformed.txt"; exit="0"; expected="invalid_output"; code=4 },
    @{ name="cli-failure"; fixture="malformed.txt"; exit="7"; expected="launch_failure"; code=3 }
  )
  foreach ($case in $cases) {
    $fixture = Join-Path $PSScriptRoot ("fixtures\" + $case.fixture)
    $resultPath = Join-Path $temp ($case.name + ".json")
    & $runner -BundlePath $bundle -ResultPath $resultPath -TimeoutSeconds 10 -MockOutputPath $fixture -MockExitCode $case.exit
    $actualCode = $LASTEXITCODE
    if ($null -eq $actualCode) { $actualCode = 0 }
    $result = Get-Content -Raw $resultPath | ConvertFrom-Json
    if ($actualCode -ne $case.code -or $result.result -ne $case.expected) { throw "$($case.name): expected $($case.expected)/$($case.code), got $($result.result)/$actualCode" }
    Write-Host "PASS $($case.name)"
  }
  $launchCommand = Join-Path $temp "mock claude launch.cmd"
  $capturedArgs = Join-Path $temp "captured-args.txt"
  @"
@echo off
echo %* > "$capturedArgs"
type "%MOCK_CLAUDE_OUTPUT%"
exit /b 0
"@ | Set-Content -LiteralPath $launchCommand -Encoding ascii
  $env:MOCK_CLAUDE_OUTPUT = Join-Path $PSScriptRoot "fixtures\approved.json"
  $launchResult = Join-Path $temp "launch-stub.json"
  & $runner -BundlePath $bundle -ResultPath $launchResult -TimeoutSeconds 10 -MockClaudeCommand $launchCommand
  $launchParsed = Get-Content -Raw $launchResult | ConvertFrom-Json
  $argsLine = Get-Content -Raw -LiteralPath $capturedArgs
  if ($launchParsed.result -ne "success") { throw "launch-stub did not return success: $($launchParsed.result) $($launchParsed.errors)" }
  if ($argsLine -notmatch '--system-prompt-file' -or $argsLine -notmatch 'skill path with space') { throw "launch-stub did not exercise space-containing prompt path arguments" }
  Write-Host "PASS launch-stub"
  $empty = Join-Path $temp "empty.md"
  New-Item -ItemType File -Path $empty | Out-Null
  $emptyResult = Join-Path $temp "empty.json"
  & $runner -BundlePath $empty -ResultPath $emptyResult
  if ($LASTEXITCODE -ne 2 -or (Get-Content -Raw $emptyResult | ConvertFrom-Json).result -ne "invalid_output") { throw "empty-bundle case failed" }
  Write-Host "PASS empty-bundle"
  $snapshot = Join-Path $root "skills\claude-adversarial-reviewer\scripts\snapshot.ps1"
  $repo = Join-Path $temp "repo"
  New-Item -ItemType Directory -Path $repo | Out-Null
  & git -C $repo init -q
  "before" | Set-Content (Join-Path $repo "untracked.txt")
  $before = Join-Path $temp "snapshot-before"
  $after = Join-Path $temp "snapshot-after"
  & $snapshot -RepoRoot $repo -OutputPath $before
  "after" | Set-Content (Join-Path $repo "untracked.txt")
  & $snapshot -RepoRoot $repo -OutputPath $after
  if ((Get-FileHash $before).Hash -eq (Get-FileHash $after).Hash) { throw "untracked mutation was not detected" }
  Write-Host "PASS untracked-mutation"
  Write-Host "Stress suite passed: 10/10"
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
