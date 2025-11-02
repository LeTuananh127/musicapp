# Log Filtering Scripts

Console bị spam bởi Android system logs? Sử dụng các scripts này để filter.

## 🪟 Windows (PowerShell)

### 1. Filter Out Noise (Recommended)
Loại bỏ AudioTrackExtImpl và các system logs spam:
```powershell
.\run_filtered.ps1
```

### 2. App Logs Only
Chỉ hiển thị logs từ app (có emoji prefix hoặc [APP]):
```powershell
.\run_app_logs_only.ps1
```

## 🐧 macOS/Linux (Bash)

### 1. Filter Out Noise (Recommended)
```bash
chmod +x run_filtered.sh
./run_filtered.sh
```

### 2. App Logs Only
```bash
chmod +x run_app_logs_only.sh
./run_app_logs_only.sh
```

## 📱 Direct adb logcat

### Filter out AudioTrackExtImpl
```bash
# macOS/Linux
adb logcat | grep -v "AudioTrackExtImpl"

# Windows PowerShell
adb logcat | Select-String -Pattern "AudioTrackExtImpl" -NotMatch
```

### Show only app logs
```bash
# macOS/Linux
adb logcat | grep -E "(\[APP\]|TrackErrorLogger|flutter)"

# Windows PowerShell
adb logcat | Select-String -Pattern "(\[APP\]|TrackErrorLogger|flutter)"
```

## 🎯 VS Code Tasks

Thêm vào `.vscode/tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Flutter: Run (Filtered)",
      "type": "shell",
      "command": "./run_filtered.sh",
      "windows": {
        "command": ".\\run_filtered.ps1"
      },
      "problemMatcher": [],
      "group": {
        "kind": "build",
        "isDefault": true
      }
    },
    {
      "label": "Flutter: App Logs Only",
      "type": "shell",
      "command": "./run_app_logs_only.sh",
      "windows": {
        "command": ".\\run_app_logs_only.ps1"
      },
      "problemMatcher": []
    }
  ]
}
```

Sau đó: `Ctrl+Shift+P` → "Tasks: Run Task" → "Flutter: Run (Filtered)"

## 🔧 Android Studio

1. Mở **Logcat** tab
2. Click dropdown "Show only selected application"
3. Hoặc thêm filter regex:
   ```
   ^(?!.*AudioTrackExtImpl).*
   ```

## ⚙️ Permanent Filter (Workspace)

Tạo file `.vscode/settings.json`:
```json
{
  "dart.flutterRunLogFile": "${workspaceFolder}/logs/flutter.log",
  "dart.maxLogLineLength": 2000,
  "files.exclude": {
    "**/logs": true
  }
}
```

Logs sẽ được ghi vào file `logs/flutter.log` thay vì console.

## 📊 Which Script to Use?

| Script | Use Case |
|--------|----------|
| `run_filtered.ps1/sh` | ✅ **Recommended** - Removes spam but keeps errors |
| `run_app_logs_only.ps1/sh` | 🎯 Very clean, only app-specific logs |
| Direct `flutter run` | ❌ Full noise, not recommended |

## 🐛 Still See AudioTrackExtImpl?

1. Make sure you're running the script (not `flutter run`)
2. Check PowerShell execution policy:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
3. Try running from terminal, not VS Code integrated terminal

## 📝 Adding Your Own Filters

Edit the scripts and add patterns to filter:

**PowerShell:**
```powershell
-not ($line -match "YourPatternHere")
```

**Bash:**
```bash
grep -v "YourPatternHere"
```

## 🚀 Quick Start

**Windows:**
```powershell
cd C:\musicapp\frontend
.\run_filtered.ps1
```

**macOS/Linux:**
```bash
cd /path/to/musicapp/frontend
chmod +x run_filtered.sh
./run_filtered.sh
```

## 💡 Pro Tips

1. **Emoji logs are easy to filter**
   - TrackErrorLogger uses: 🔴📁📄✅❌
   - Add emojis to your own logs for easy filtering

2. **Use prefixes**
   ```dart
   print('[APP] Your message'); // Easy to filter
   ```

3. **Redirect to file**
   ```bash
   flutter run > logs.txt 2>&1
   tail -f logs.txt | grep -v "AudioTrackExtImpl"
   ```

4. **Color code your logs**
   - VS Code terminal supports ANSI colors
   - Emojis stand out visually

## ❓ Why Can't We Disable It?

`AudioTrackExtImpl` is an **Android OS system log**, not from your app. You can only:
- ✅ Filter it in your terminal/IDE
- ✅ Ignore it (doesn't affect anything)
- ❌ Cannot disable at source

It's harmless - just visual noise! 🎵
