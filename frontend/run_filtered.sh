#!/bin/bash
# Flutter Run with Filtered Logs
# Filters out annoying Android system logs

echo -e "\033[36mStarting Flutter with filtered logs...\033[0m"
echo -e "\033[33mFiltering out: AudioTrackExtImpl, EGL_emulation, etc.\033[0m"
echo ""

# Run flutter and filter out noise
flutter run 2>&1 | grep -v -E "(AudioTrackExtImpl|EGL_emulation|eglCodecCommon|HostConnection|checkBoostPermission)"
