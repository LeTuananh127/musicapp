# Track Error Logger - CSV File Location

## 📁 File Location

File CSV chứa danh sách các bài hát bị lỗi 403 được lưu tại:

```
frontend/lib/shared/services/track_errors_403.csv
```

## 📊 CSV Format

File CSV có cấu trúc như sau:

```csv
timestamp,track_id,title,artist,preview_url,cover_url,error_details
2024-11-02T10:30:45.123Z,12345,"Song Title","Artist Name","https://...",https://...","403 Forbidden"
```

### Các cột trong CSV:
- **timestamp**: Thời điểm xảy ra lỗi (ISO 8601 format)
- **track_id**: ID của bài hát
- **title**: Tên bài hát
- **artist**: Tên nghệ sĩ
- **preview_url**: Link preview (nếu có)
- **cover_url**: Link ảnh bìa (nếu có)
- **error_details**: Chi tiết lỗi (mặc định: "403 Forbidden")

## 🔍 Xem file trong VS Code

1. Mở Explorer (Ctrl+Shift+E)
2. Navigate to: `frontend/lib/shared/services/`
3. Mở file `track_errors_403.csv`

## 🗑️ Xóa logs

```dart
await TrackErrorLogger.clearLogs();
```

## 📖 Đọc tất cả errors

```dart
final errors = await TrackErrorLogger.getAllErrors();
for (var error in errors) {
  print('${error['timestamp']}: ${error['title']} by ${error['artist']}');
}
```

## ℹ️ Lưu ý

- File CSV được tạo tự động khi có lỗi 403 đầu tiên
- File nằm cùng trong project, dễ dàng access và version control
- Console sẽ hiển thị đường dẫn file khi app khởi động
- Mỗi lỗi 403 mới sẽ được append vào cuối file
