# Tìm File CSV Track Errors 403

## Vấn đề
Bạn thấy lỗi 403 trong console nhưng chưa tìm thấy file CSV.

## Giải pháp

### 1. Kiểm tra Console Output

Khi app khởi động hoặc mở Error Log screen, console sẽ in ra đường dẫn:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 Track 403 Error Log File Location:
   C:\Users\YourName\Documents\track_errors_403.csv
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Copy đường dẫn này và mở bằng:
- File Explorer (Windows)
- Excel
- Notepad
- VS Code

### 2. Vị Trí File Theo Platform

#### Windows Desktop
```
C:\Users\{Username}\Documents\track_errors_403.csv
```

#### Android (Emulator hoặc Device)
```
/storage/emulated/0/Documents/track_errors_403.csv
```

Để lấy file từ Android:
```bash
# List files
adb shell ls /storage/emulated/0/Documents/

# Pull file to desktop
adb pull /storage/emulated/0/Documents/track_errors_403.csv ./
```

#### iOS (Simulator)
```
~/Library/Developer/CoreSimulator/Devices/{DEVICE_ID}/data/Containers/Data/Application/{APP_ID}/Documents/track_errors_403.csv
```

Hoặc dùng Xcode:
1. Window → Devices and Simulators
2. Chọn device/simulator
3. Installed Apps → {Your App}
4. Download Container
5. Giải nén → AppData → Documents → track_errors_403.csv

#### macOS Desktop
```
~/Documents/track_errors_403.csv
```

### 3. Xem Trong App

1. Mở app
2. Play một bài hát (để mini player hiển thị)
3. Tap nút menu (⋮) trên mini player
4. Chọn "Error Logs (403)"
5. Màn hình hiển thị:
   - Đường dẫn file CSV
   - Danh sách tracks bị lỗi
   - Tổng số lỗi

### 4. Debug - Kiểm tra File Có Tồn Tại

Trong console output, tìm dòng:
```
✅ File exists with X lines (including header)
   Total errors logged: Y
```

Hoặc:
```
ℹ️  File does not exist yet (no errors logged)
```

### 5. Kiểm Tra Logs Khi Có 403

Khi track bị lỗi 403, console sẽ in:
```
🔴 [TrackErrorLogger] Starting to log 403 error for track: 240803 - Song Name
📁 [TrackErrorLogger] Documents directory: C:\Users\...\Documents
📄 [TrackErrorLogger] CSV file path: C:\Users\...\Documents\track_errors_403.csv
✓ [TrackErrorLogger] File exists: false
📝 [TrackErrorLogger] Wrote CSV header
✅ [TrackErrorLogger] Successfully logged 403 error for track: Song Name (240803)
   File location: C:\Users\...\Documents\track_errors_403.csv
```

Nếu thấy:
```
❌ [TrackErrorLogger] Failed to log 403 error: ...
   Stack trace: ...
```

→ Có lỗi khi ghi file (permission, disk full, etc.)

### 6. Hot Restart Required

Nếu bạn vừa thêm code TrackErrorLogger:

1. **Hot Restart** (không phải hot reload)
   - VS Code: Ctrl+Shift+F5
   - Terminal: `r` trong flutter run
   - Android Studio: Stop → Run

2. File CSV chỉ được tạo khi:
   - App restart
   - Track đầu tiên bị 403

### 7. Test Logging

Để test xem logging có hoạt động:

1. Restart app hoàn toàn
2. Chờ console in đường dẫn file
3. Play một track bị 403
4. Kiểm tra console có thông báo "✅ Successfully logged"
5. Mở file CSV theo đường dẫn đã in

### 8. Common Issues

#### File không tồn tại
- ✅ App chưa restart sau khi thêm code
- ✅ Chưa có track nào bị 403 thật sự
- ✅ Logging code bị lỗi (xem stack trace)

#### Không thấy logs trong console
- ✅ Filter console bị bật (tắt filter)
- ✅ Console buffer đầy (clear console)
- ✅ Restart app

#### Permission denied
- ✅ Android: Cần WRITE_EXTERNAL_STORAGE permission
- ✅ iOS: Documents folder luôn writable
- ✅ Desktop: Check user permissions

### 9. Mở File CSV

#### Windows
```powershell
# File Explorer
explorer C:\Users\{Username}\Documents

# Notepad
notepad C:\Users\{Username}\Documents\track_errors_403.csv

# Excel
start excel "C:\Users\{Username}\Documents\track_errors_403.csv"

# VS Code
code "C:\Users\{Username}\Documents\track_errors_403.csv"
```

#### macOS/Linux
```bash
# Finder/File manager
open ~/Documents

# Text editor
cat ~/Documents/track_errors_403.csv

# Excel (if installed)
open -a "Microsoft Excel" ~/Documents/track_errors_403.csv

# VS Code
code ~/Documents/track_errors_403.csv
```

### 10. CSV Format

File có format:
```csv
timestamp,track_id,title,artist,preview_url,cover_url,error_details
2025-11-02T10:30:45.123Z,240803,"Song Name","Artist Name","http://...","http://...","HEAD request returned 403"
```

Mở bằng:
- Excel/Google Sheets (tự động parse columns)
- Text editor (xem raw)
- Python pandas: `pd.read_csv('track_errors_403.csv')`

## Quick Command

**Copy ngay đường dẫn từ console → Open File Explorer → Paste vào address bar → Enter**

Hoặc trong VS Code terminal:
```bash
# Windows
explorer.exe %USERPROFILE%\Documents

# macOS
open ~/Documents
```
