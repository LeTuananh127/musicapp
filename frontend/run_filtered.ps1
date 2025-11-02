# Flutter Run with Filtered Logs
# Filters out annoying Android system logs

Write-Host "Starting Flutter with filtered logs..." -ForegroundColor Cyan
Write-Host "Filtering out: AudioTrackExtImpl, EGL_emulation, etc." -ForegroundColor Yellow
Write-Host ""

# Run flutter and filter out noise
flutter run 2>&1 | Where-Object {
    $line = $_.ToString()
    
    # Filter out these patterns
    -not ($line -match "AudioTrackExtImpl") -and
    -not ($line -match "EGL_emulation") -and
    -not ($line -match "eglCodecCommon") -and
    -not ($line -match "HostConnection") -and
    -not ($line -match "checkBoostPermission")
}
