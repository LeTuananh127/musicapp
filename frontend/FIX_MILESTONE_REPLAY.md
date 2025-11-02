# Fix: Milestones không được ghi khi nghe lại track

## Vấn đề

Khi nghe một bài hát lần đầu, milestones (25%, 50%, 75%, 100%) được ghi đúng vào database:
```
milestone: 25, 50, 75, 100
```

Nhưng khi nghe lại cùng bài hát lần 2, 3..., các milestones không được ghi nữa:
```
milestone: null
```

## Nguyên nhân

`PlayerController` sử dụng `_milestonesHit` cache để tránh ghi duplicate milestones:

```dart
Map<String, Set<int>>? _milestonesHit; // track.id -> {25,50,75,100}
```

Cache này lưu lại các milestones đã hit cho mỗi track ID. Khi track được play lại:
1. Code kiểm tra `msSet.contains(pct)` 
2. Nếu đã hit milestone này rồi → skip (return false)
3. Kết quả: không log milestone nữa

**Cache không bao giờ được clear**, nên một khi đã nghe hết bài (hit 100%), mọi lần nghe sau đều bị skip.

## Giải pháp

Reset `_milestonesHit` cache cho track mỗi khi:

### 1. Play track mới (`playTrack`)
```dart
_milestonesHit?.remove(track.id);
```

### 2. Play queue (`playQueue`) 
```dart
_milestonesHit?.remove(start.id);
```

### 3. Next track
```dart
_milestonesHit?.remove(nextTrack.id);
```

### 4. Previous track
```dart
_milestonesHit?.remove(prevTrack.id);
```

### 5. Jump to track
```dart
_milestonesHit?.remove(track.id);
```

### 6. Repeat One - restart track
Có 2 nơi cần reset:

**a) Trong `playerStateStream.listen` (khi track complete tự động)**
```dart
if (state.repeatMode == RepeatMode.one) {
  final cur = state.current;
  if (cur != null) {
    _milestonesHit?.remove(cur.id);
    _loggedTrackId = null;
  }
  // ... seek và play lại
}
```

**b) Trong `_startTick` timer (fallback cho simulated tracks)**
```dart
if (pos >= dur) {
  if (mark(100)) _logInteraction(completed: true, milestone: 100);
  if (state.repeatMode == RepeatMode.one) {
    _milestonesHit?.remove(cur.id);
    _loggedTrackId = null;
    // ... restart
  }
}
```

## Test cases

### Case 1: Play track 2 lần liên tiếp
```
Play track A → milestones: 25, 50, 75, 100 ✓
Play track A again → milestones: 25, 50, 75, 100 ✓ (FIXED)
```

### Case 2: Play queue với same track
```
Queue: [A, B, A]
Play A (first) → milestones: 25, 50, 75, 100 ✓
Next to B → milestones: 25, 50, 75, 100 ✓
Next to A (second) → milestones: 25, 50, 75, 100 ✓ (FIXED)
```

### Case 3: Repeat One
```
Play A with RepeatMode.one
  Listen 1 → milestones: 25, 50, 75, 100 ✓
  Auto restart → milestones: 25, 50, 75, 100 ✓ (FIXED)
  Auto restart → milestones: 25, 50, 75, 100 ✓ (FIXED)
```

### Case 4: Previous/Next navigation
```
Queue: [A, B]
Play A → milestones: 25, 50, 75, 100 ✓
Next to B → milestones: 25, 50, 75, 100 ✓
Previous to A → milestones: 25, 50, 75, 100 ✓ (FIXED)
```

## Lưu ý

### 1. Không reset toàn bộ cache
Chỉ reset entry cho track đang play:
```dart
_milestonesHit?.remove(track.id); // ✓ Chỉ xóa 1 track
// NOT: _milestonesHit?.clear(); // ✗ Xóa tất cả
```

Lý do: Giữ cache cho các tracks khác để avoid duplicate milestones khi:
- User skip nhanh qua nhiều tracks
- Play queue có duplicate tracks ở khác position

### 2. Reset cùng với `_loggedTrackId`
Luôn reset cả 2 cùng lúc:
```dart
_loggedTrackId = null;
_milestonesHit?.remove(track.id);
```

Đảm bảo consistent behavior cho cả:
- Initial play log (0 seconds)
- Milestone logs (25%, 50%, 75%, 100%)

### 3. Safe null-aware operation
Sử dụng `?.remove()` thay vì `.remove()`:
```dart
_milestonesHit?.remove(track.id); // ✓ Safe nếu null
```

Cache có thể null khi:
- First time play (chưa init)
- Memory cleared

## Database impact

### Trước fix
```sql
SELECT track_id, milestone, COUNT(*) 
FROM interactions 
WHERE track_id = 241068 
GROUP BY milestone;

-- Result:
-- 25: 1 row
-- 50: 1 row  
-- 75: 1 row
-- 100: 1 row
-- null: 50+ rows (lần nghe lại)
```

### Sau fix
```sql
SELECT track_id, milestone, COUNT(*) 
FROM interactions 
WHERE track_id = 241068 
GROUP BY milestone;

-- Result:
-- 25: 5 rows (nghe 5 lần)
-- 50: 5 rows
-- 75: 5 rows
-- 100: 5 rows
-- null: ~0 rows (chỉ có periodic logs mỗi 10s)
```

## Code locations

File: `lib/features/player/application/player_providers.dart`

Changes:
1. Line ~138: `playTrack()` - reset khi play single track
2. Line ~275: `playQueue()` - reset khi play queue
3. Line ~319: `next()` - reset khi next
4. Line ~358: `previous()` - reset khi previous  
5. Line ~396: `jumpTo()` - reset khi jump to index
6. Line ~86: `playerStateStream` - reset khi auto-restart (RepeatMode.one)
7. Line ~913: `_startTick` - reset khi manual restart (RepeatMode.one, simulated)

Total: 7 locations
