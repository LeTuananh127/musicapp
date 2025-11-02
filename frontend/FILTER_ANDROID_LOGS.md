# Android Log Filtering

## Vấn đề
Console bị spam bởi log:
```
D/AudioTrackExtImpl: checkBoostPermission, audioBoostEnable is disabled
```

Đây là debug log của Android system, không ảnh hưởng đến app.

## Giải pháp

### 1. Filter trong Android Studio

**File → Settings → Editor → General → Console**
- Chọn "Fold console lines that contain"
- Thêm pattern: `AudioTrackExtImpl`

Hoặc trong logcat filter:
```
tag:^(?!AudioTrackExtImpl)
```

### 2. Filter trong VS Code

Sử dụng extension "Logcat" hoặc filter trong terminal.

### 3. Filter trong adb logcat

```bash
# Exclude AudioTrackExtImpl
adb logcat | grep -v "AudioTrackExtImpl"

# Only show app logs
adb logcat | grep "flutter"

# Filter multiple tags
adb logcat -s flutter:V *:E
```

### 4. Flutter Run với Log Level

```bash
# Chỉ show warning và error
flutter run --verbose=false

# Hoặc set log level
flutter run -v
```

### 5. Programmatic Filtering (Android)

Nếu muốn tắt hẳn trong code, tạo file Android native:

**android/app/src/main/kotlin/..../MainActivity.kt**
```kotlin
import android.util.Log

class CustomLogFilter {
    companion object {
        @JvmStatic
        fun suppressAudioLogs() {
            // This won't work for system logs, but you can set app log level
            // System logs like AudioTrackExtImpl are from Android OS
        }
    }
}
```

**KHÔNG THỂ TẮT** vì đây là system log, chỉ có thể filter.

### 6. Workaround - Focus on App Logs

Thêm prefix cho app logs để dễ filter:

**lib/shared/utils/logger.dart** (tạo mới)
```dart
class AppLogger {
  static void debug(String message) {
    print('🔵 [APP] $message');
  }
  
  static void info(String message) {
    print('ℹ️ [APP] $message');
  }
  
  static void warning(String message) {
    print('⚠️ [APP] $message');
  }
  
  static void error(String message) {
    print('❌ [APP] $message');
  }
}
```

Sau đó filter chỉ show `[APP]`:
```bash
adb logcat | grep "\[APP\]"
```

### 7. Android Studio Logcat Filter

1. Mở Logcat tab
2. Chọn dropdown "Show only selected application"
3. Hoặc thêm filter:
   ```
   tag:^(?!AudioTrackExtImpl).*
   ```

### 8. VSCode Flutter Extension

Settings → Extensions → Dart & Flutter:
- `dart.flutterRunLogFile`: Ghi log vào file thay vì console
- `dart.maxLogLineLength`: Giới hạn độ dài log line

### 9. Quick Filter Script (PowerShell)

**filter_logs.ps1**
```powershell
adb logcat | Select-String -Pattern "AudioTrackExtImpl" -NotMatch
```

Run:
```powershell
.\filter_logs.ps1
```

### 10. Long-term Solution

**android/app/src/main/AndroidManifest.xml**

Không có cách tắt log này vì nó từ Android OS, nhưng có thể:
1. ✅ Filter trong IDE/terminal
2. ✅ Chỉ focus vào app logs (có prefix đặc biệt)
3. ✅ Sử dụng log aggregation tool (như Sentry)
4. ❌ KHÔNG thể tắt system logs

## Tóm Tắt

**Logs này KHÔNG ẢNH HƯỞNG đến:**
- ✅ App performance
- ✅ Audio playback
- ✅ TrackErrorLogger CSV
- ✅ User experience

**Chỉ làm:**
- ⚠️ Console spam (visual noise)

**Best practice:**
1. Filter console: `grep -v "AudioTrackExtImpl"`
2. Focus on app logs có prefix `[APP]`
3. Sử dụng logcat filters trong IDE
4. Ignore nó - không ảnh hưởng gì

## Console Filter Commands

### Bash/Linux/macOS
```bash
# Filter out AudioTrackExtImpl
flutter run 2>&1 | grep -v "AudioTrackExtImpl"

# Only show app logs
flutter run 2>&1 | grep "\[APP\]"

# Multiple filters
flutter run 2>&1 | grep -v -E "(AudioTrackExtImpl|EGL_emulation)"
```

### PowerShell (Windows)
```powershell
# Filter out
flutter run 2>&1 | Select-String -Pattern "AudioTrackExtImpl" -NotMatch

# Only show errors and app logs
flutter run 2>&1 | Select-String -Pattern "(ERROR|\[APP\])"
```

### CMD (Windows)
```cmd
flutter run 2>&1 | findstr /V "AudioTrackExtImpl"
```
