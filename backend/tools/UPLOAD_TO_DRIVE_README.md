# Upload Deezer cache to Google Drive (rclone)

This document explains how to upload the local Deezer preview cache to Google Drive using `rclone` and the helper PowerShell script `upload_to_drive.ps1`.

Prerequisites
- Install rclone: https://rclone.org/install/
- Configure a remote (example name: `gdrive`) by running `rclone config` and following the interactive auth flow.
- Ensure `rclone` is in your PATH so PowerShell can call it.

Quick steps (PowerShell)

1. Dry-run to see what would be uploaded:

```powershell
cd C:\musicapp\backend\tools
.\upload_to_drive.ps1 -DryRun
```

2. Upload to remote `gdrive` into `MusicApp/previews`:

```powershell
.\upload_to_drive.ps1 -Remote gdrive -RemotePath "MusicApp/previews"
```

3. Upload and delete local files after successful upload (will prompt for confirmation):

```powershell
.\upload_to_drive.ps1 -Remote gdrive -RemotePath "MusicApp/previews" -DeleteAfter
```

4. Skip delete confirmation by adding `-Force`:

```powershell
.\upload_to_drive.ps1 -Remote gdrive -RemotePath "MusicApp/previews" -DeleteAfter -Force
```

Scheduling (Windows Task Scheduler)
- Create a task that runs PowerShell with an argument to call the script. Example action command:

```text
Program/script: powershell.exe
Add arguments: -NoProfile -ExecutionPolicy Bypass -File "C:\musicapp\backend\tools\upload_to_drive.ps1" -Remote gdrive -RemotePath "MusicApp/previews" -DeleteAfter -Force
```

Notes
- The script defaults to the repo cache: `..\app\static\audio\deezer` relative to the `tools` folder. Use `-SourcePath` to change it.
- `rclone copy` is used (not `sync`) to avoid accidental deletions on the remote. If you want exact mirroring, modify the script to use `sync` instead.
