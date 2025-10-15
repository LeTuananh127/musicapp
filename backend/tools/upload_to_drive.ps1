<#
.SYNOPSIS
  Upload local Deezer preview cache to a configured rclone remote (e.g. Google Drive).

.DESCRIPTION
  This script invokes `rclone` to copy the folder containing preview MP3s to a remote.
  It supports a dry-run mode and an optional delete-after-upload step.

.EXAMPLE
  # Dry run (shows what would be uploaded)
  .\upload_to_drive.ps1 -DryRun

.EXAMPLE
  # Upload to remote 'gdrive' into folder 'MusicApp/previews' and then delete local files
  .\upload_to_drive.ps1 -Remote gdrive -RemotePath "MusicApp/previews" -DeleteAfter

.NOTES
  - Requires rclone to be installed and a remote (e.g. 'gdrive') configured via `rclone config`.
  - Run this from the repo path C:\musicapp\backend or provide -SourcePath explicitly.
#>

[CmdletBinding()]
param(
    [string]$SourcePath = "$PSScriptRoot\..\app\static\audio\deezer",
    [string]$Remote = "gdrive",
    [string]$RemotePath = "MusicApp/previews",
    [switch]$DeleteAfter,
    [switch]$DryRun,
    [switch]$Force
)

function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Err  { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

try {
    $resolved = Resolve-Path -Path $SourcePath -ErrorAction Stop
    $localPath = $resolved.Path
} catch {
    Write-Err "Source path not found: $SourcePath"
    exit 2
}

if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    Write-Err "rclone not found in PATH. Install rclone and configure a remote (see https://rclone.org/).
Run 'rclone config' to create a remote named 'gdrive' or choose a different name with -Remote.";
    exit 3
}

$fullRemote = "${Remote}:${RemotePath}"

Write-Info "Source: $localPath"
Write-Info "Remote: $fullRemote"
if ($DryRun) { Write-Info "Running in DryRun mode (no files will be transferred)." }
if ($DeleteAfter) { Write-Info "Files will be deleted locally after successful upload." }

$rcloneArgs = @("copy", "`"$localPath`"", "`"$fullRemote`"", "--progress", "--transfers=8", "--checkers=8", "--retries=3", "--low-level-retries=5")
if ($DryRun) { $rcloneArgs += "--dry-run" }

Write-Info "Running: rclone $([string]::Join(' ', $rcloneArgs))"

$proc = Start-Process -FilePath rclone -ArgumentList $rcloneArgs -NoNewWindow -Wait -PassThru -WindowStyle Hidden
if ($proc.ExitCode -ne 0) {
    Write-Err "rclone exited with code $($proc.ExitCode). Upload may have failed."
    exit $proc.ExitCode
}

Write-Info "rclone finished successfully."

if ($DeleteAfter -and -not $DryRun) {
    if (-not $Force) {
        $confirm = Read-Host "Delete local files under $localPath after upload? Type 'yes' to confirm"
        if ($confirm -ne 'yes') {
            Write-Info "Aborting delete step. Files were NOT removed. Rerun with -Force to skip confirmation."
            exit 0
        }
    }

    Write-Info "Removing files under $localPath..."
    try {
        Get-ChildItem -Path $localPath -File -Recurse | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
        }
        Write-Info "Local files deleted."
    } catch {
        Write-Err "Failed to delete some files: $_"
        exit 6
    }
}

Write-Info "Done."
