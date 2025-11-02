# Show Only App Logs
# Only displays logs from your Flutter app with [APP], [TrackErrorLogger], etc.

Write-Host "Starting Flutter - Showing ONLY app logs..." -ForegroundColor Cyan
Write-Host "Looking for: [APP], [TrackErrorLogger], ERROR, WARNING" -ForegroundColor Yellow
Write-Host ""

# Run flutter and only show app-specific logs
flutter run 2>&1 | Where-Object {
    $line = $_.ToString()
    
    # Only show these patterns
    ($line -match "\[APP\]") -or
    ($line -match "\[TrackErrorLogger\]") -or
    ($line -match "ERROR") -or
    ($line -match "WARN") -or
    ($line -match "Exception") -or
    ($line -match "🔴|🔵|ℹ️|⚠️|❌|✅|📝|📁|📄") # Emoji prefixes
}
