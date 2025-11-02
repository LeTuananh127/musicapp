# Track Error Logger (403)

## Tổng quan
Hệ thống này tự động ghi lại các track bị lỗi 403 (Forbidden) khi phát nhạc vào file CSV để phân tích sau.

## Tính năng

### 1. Ghi Log Tự Động
Mỗi khi một track bị lỗi 403 trong các trường hợp sau:
- Phát track đơn lẻ
- Phát queue/playlist
- Quét và kiểm tra preview URL
- Thử HEAD hoặc GET request

Thông tin sau được ghi lại:
- **timestamp**: Thời gian xảy ra lỗi (ISO 8601)
- **track_id**: ID của track
- **title**: Tên bài hát
- **artist**: Tên nghệ sĩ
- **preview_url**: URL preview bị lỗi
- **cover_url**: URL cover ảnh
- **error_details**: Chi tiết lỗi (HTTP status code, context)

### 2. Vị Trí File CSV
File được lưu tại: `Documents/track_errors_403.csv`

Trên Android: `/storage/emulated/0/Documents/track_errors_403.csv`
Trên iOS: `~/Documents/track_errors_403.csv`

### 3. Truy Cập Error Logs
Có 2 cách:
1. **Từ Mini Player**: Tap nút menu (⋮) → "Error Logs (403)"
2. **Trực tiếp**: Mở file CSV từ Documents folder

### 4. Màn Hình Error Log
- Hiển thị danh sách tất cả tracks bị lỗi
- Thông tin: Title, Artist, ID, Timestamp, Error details
- Nút **Refresh** (🔄): Tải lại danh sách
- Nút **Clear** (🗑️): Xóa tất cả logs
- Tap vào track để xem thông tin chi tiết

## Cấu trúc CSV

```csv
timestamp,track_id,title,artist,preview_url,cover_url,error_details
2025-11-02T10:30:45.123Z,12345,"Song Title","Artist Name","https://api.deezer.com/track/12345/preview","https://api.deezer.com/album/678/image","HEAD request returned 403"
```

## API

### TrackErrorLogger

```dart
// Ghi log một track bị lỗi 403
await TrackErrorLogger.log403Error(
  track,
  errorDetails: 'HEAD request returned 403'
);

// Lấy đường dẫn file CSV
String path = await TrackErrorLogger.getLogFilePath();

// Lấy tất cả errors dưới dạng List<Map>
List<Map<String, String>> errors = await TrackErrorLogger.getAllErrors();

// Xóa tất cả logs
await TrackErrorLogger.clearLogs();
```

## Tích hợp

### player_providers.dart
Các điểm ghi log:
1. `playTrack()`: Khi single track check trả về 403
2. `_filterAvailable()`: Khi HEAD hoặc GET request trả về 403
3. `scanAndRemoveForbiddenTracks()`: Khi quét queue tìm thấy 403

### mini_player_bar.dart
Menu button để truy cập TrackErrorLogScreen

## Sử dụng

### Phát hiện patterns
```dart
// Lấy tất cả errors
final errors = await TrackErrorLogger.getAllErrors();

// Tìm tracks bị lỗi nhiều nhất
final trackCounts = <String, int>{};
for (var e in errors) {
  final id = e['track_id']!;
  trackCounts[id] = (trackCounts[id] ?? 0) + 1;
}

// Tìm preview URLs có vấn đề
final urlCounts = <String, int>{};
for (var e in errors) {
  final url = e['preview_url']!;
  urlCounts[url] = (urlCounts[url] ?? 0) + 1;
}
```

### Export và phân tích
File CSV có thể:
- Mở bằng Excel/Google Sheets
- Import vào database để phân tích
- Share với team để debug
- Sử dụng trong automated tests

## Lưu ý

1. **Performance**: Ghi file là async operation, không block UI
2. **Error Handling**: Nếu ghi file thất bại, chỉ log console, không crash app
3. **Privacy**: File lưu trong Documents (user-accessible), không có sensitive data
4. **Disk Space**: File CSV nhỏ (~1KB per 10 tracks), có thể clear định kỳ

## Ví dụ Output

```csv
timestamp,track_id,title,artist,preview_url,cover_url,error_details
2025-11-02T10:30:45.123Z,12345,"Happy Song","Artist A","https://api.deezer.com/track/12345/preview","https://api.deezer.com/album/678/image","HEAD request returned 403"
2025-11-02T10:31:12.456Z,67890,"Sad Song","Artist B","https://api.deezer.com/track/67890/preview","https://api.deezer.com/album/999/image","Ranged GET (after 405) returned 403"
2025-11-02T10:32:03.789Z,11111,"Rock Song","Artist C","https://api.deezer.com/track/11111/preview","","Single track 403 check failed"
```

## Troubleshooting

### File không tồn tại
- Chưa có track nào bị lỗi 403
- Kiểm tra permissions (Android storage)

### Không thấy nút menu
- Cần có track đang phát (mini player hiển thị)
- Restart app nếu vừa update code

### Error logs trống
- Tất cả tracks đang hoạt động tốt
- Hoặc đã clear logs trước đó
