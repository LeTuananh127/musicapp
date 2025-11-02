#!/bin/bash
# Show Only App Logs
# Only displays logs from your Flutter app

echo -e "\033[36mStarting Flutter - Showing ONLY app logs...\033[0m"
echo -e "\033[33mLooking for: [APP], [TrackErrorLogger], ERROR, WARNING\033[0m"
echo ""

# Run flutter and only show app-specific logs
flutter run 2>&1 | grep -E "(\[APP\]|\[TrackErrorLogger\]|ERROR|WARN|Exception|🔴|🔵|ℹ️|⚠️|❌|✅|📝|📁|📄)"
