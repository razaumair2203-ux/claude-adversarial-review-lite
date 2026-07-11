[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $RepoRoot).Path

function Get-GitNullPaths([string[]]$GitArguments) {
  $temp = [IO.Path]::GetTempFileName()
  try {
    $args = @("-c", "core.quotePath=false", "-C", ('"' + $root + '"')) + $GitArguments
    $process = Start-Process -FilePath "git" -ArgumentList $args -RedirectStandardOutput $temp -PassThru -WindowStyle Hidden -Wait
    if ($process.ExitCode -ne 0) { throw "Git path enumeration failed." }
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($temp))
    return @($text.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
  } finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  }
}

$status = & git -C $root status --porcelain=v1 --untracked-files=all
if ($LASTEXITCODE -ne 0) { throw "Git status failed." }
$lines = @("status") + @($status | Sort-Object) + @("dirty-tracked-sha256")
$dirty = Get-GitNullPaths @("diff", "--name-only", "--diff-filter=ACMRTUXB", "-z")
$dirty += Get-GitNullPaths @("diff", "--cached", "--name-only", "--diff-filter=ACMRTUXB", "-z")
foreach ($path in @($dirty | Sort-Object -Unique)) {
  $full = Join-Path $root $path
  if (Test-Path -LiteralPath $full -PathType Leaf) { $lines += "$((Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLower())  $path" }
}
$lines += "untracked-sha256"
$untracked = Get-GitNullPaths @("ls-files", "--others", "--exclude-standard", "-z")
foreach ($path in @($untracked | Sort-Object -Unique)) {
  $full = Join-Path $root $path
  if (Test-Path -LiteralPath $full -PathType Leaf) { $lines += "$((Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLower())  $path" }
}
$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$lines | Set-Content -LiteralPath $OutputPath -Encoding utf8
