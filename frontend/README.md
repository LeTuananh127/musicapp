# Music Streaming App (Flutter Frontend)

This is the Flutter client for the full‑stack music streaming platform. It connects to the FastAPI backend for authentication, track browsing, playback, recommendations, interaction logging, and playlist management.

## Stack
* Flutter 3 / Dart 3
* Riverpod (state management)
* go_router (navigation + ShellRoute tabs)
* Dio (HTTP client with auth interceptor)
* Freezed + json_serializable (immutable models / DTOs)
* just_audio (gapless audio playback)
* flutter_secure_storage (persist JWT securely)

## Architecture Overview
Feature‑first modular structure for scalability:
```
lib/
	core/                # Cross-cutting concerns (routing, theme, http, widgets)
	data/                # DTOs + repositories (API bridge)
	features/            # Vertical slices (UI + providers + logic)
		auth/
		recommend/
		playlist/
		player/
		browse/
	main.dart
```
Principles:
* UI reads reactive state from Riverpod providers.
* Repositories encapsulate REST calls (swap later for GraphQL / gRPC or caching).
* Minimal logic inside widgets; business decisions in providers.

## Environment Config
Backend base URL is defined in network/config code (adjust to your FastAPI host, e.g. `http://127.0.0.1:8000`). Consider adding runtime `.env` loader for multi‑env builds later.

## Setup
```
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run
```
Dev loop:
```
flutter pub run build_runner watch --delete-conflicting-outputs
```

## Auth Flow
1. User registers (`/auth/register`) or logs in (`/auth/login`).
2. Backend returns `{ access_token, token_type, user_id }`.
3. Token stored via secure storage; provider marks user authenticated.
4. Dio interceptor adds `Authorization: Bearer <token>` automatically.
5. Logout clears secure storage and invalidates provider state.
6. `/auth/me` automatically called post login/register & on cold start restore to retrieve profile (display_name).

Password hashing backend recently switched to `pbkdf2_sha256` (with bcrypt fallback) for Windows stability—no client impact.

## Playlists
* List: GET `/playlists/`
* Create: POST `/playlists/` (UI dialog)
* Detail meta: GET `/playlists/{id}` (track_count, visibility)
* Tracks: GET `/playlists/{id}/tracks` (ordered by position)
* Add track: POST `/playlists/{id}/tracks` (from Home & Recommend UI)
* Remove track: DELETE `/playlists/{id}/tracks/{track_id}` (detail screen)
* UI Features: pull-to-refresh, optimistic removal, heart (like) toggles per track
* Reorder: kéo thả (ReorderableListView) gọi PATCH `/playlists/{id}/reorder`
* Roadmap: share links, collaborative editing

## Likes
* Like: POST `/tracks/{id}/like`
* Unlike: DELETE `/tracks/{id}/like`
* Fetch liked set: GET `/tracks/liked` -> `{ liked: [ids] }`
* Optimistic UI hearts on Home & Playlist Detail (rollback on failure)
* "Liked Songs" virtual playlist screen (client-side aggregation)

## Mini Player (Prototype)
* Controller: `playerControllerProvider` (Riverpod StateNotifier)
* UI: play/pause icons inline trong Home, Playlist Detail, Liked Songs
* Tạm thời KHÔNG stream audio thật: mô phỏng playback state + thời gian (chưa cần source preview)
* Interaction logging: mỗi hành động play/pause/log kết thúc gọi `POST /interactions/` với các field: `track_id`, `seconds_listened`, `is_completed`
* Sau này: tích hợp real preview URL hoặc HLS, thêm queue & background audio
* Mini bar cố định: `MiniPlayerBar` ở cuối mỗi tab (title + progress + controls)
* Timer giả lập: tăng position mỗi giây đến đủ `durationMs` rồi tự đánh dấu complete

## Recommendations (Current Placeholder)
Simple heuristic scoring (popularity + small random jitter). Roadmap:
* Implicit feedback matrix factorization (ALS/implicit)
* Audio feature enrichment (tempo, valence, energy, spectral features)
* Hybrid rank fusion & session‑aware re‑ranking

## Interaction Logging
Play / complete events posted to backend to improve future recommendation quality. Extend later with skip, like, rating events.

## Web (Chrome) Notes
When running Flutter Web, prefer `http://127.0.0.1:8000` instead of `http://localhost:8000` to avoid occasional browser host resolution or CORS edge cases. All repositories now read the API base from a single `AppConfig` so you only change it in one place (`core/config/app_env.dart`). If you see a generic `DioException [connection error]` during register/login on web, verify:
1. Backend is reachable directly in the browser.
2. The origin (`http://localhost:<port>`) is allowed by backend CORS (in dev you may temporarily use `allow_origins=['*']`).
3. The base URL in `AppConfig.dev` matches the backend host.

## Quality & Lints
`flutter_lints` enabled. Run:
```
flutter analyze
```
Customize rules in `analysis_options.yaml`.

## Testing (Initial Strategy)
* Widget tests around playlist & auth flows (TBD)
* Repository tests with mocked Dio (TBD)

## Troubleshooting
| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| 401 on API calls | Missing/expired JWT | Re-login (token refresh) |
| Decode errors | Model drift vs backend | Regenerate models, confirm endpoints |
| Stuck on login screen | Token not persisted | Check secure storage & interceptor logic |

## Roadmap
* Mood / audio feature visualization
* Advanced recsys pipeline & caching
* Search + artist/album detail pages
* Offline caching / downloads
* Track removal & reorder in playlists
* Theming + dark mode polish
* i18n (ARB) integration

## Contributing
1. Branch from `main`
2. Add/modify models (run build_runner)
3. Implement feature slice (UI + provider + repository)
4. Add tests & run analyzer
5. Open PR

## License
Private / Internal (update if publishing)
