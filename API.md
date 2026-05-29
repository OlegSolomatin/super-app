# API Endpoints Super-App

## Аутентификация
```
POST   /api/v1/auth/register     { email, pass, username } → TokenResponse
POST   /api/v1/auth/login        { email, pass } → TokenResponse
POST   /api/v1/auth/refresh      { refresh_token } → TokenResponse
GET    /api/v1/users/me          → UserResponse
PATCH  /api/v1/users/me          { username, bio, avatar } → UserResponse
```

## Посты (социальная сеть)
```
GET    /api/v1/posts             ?page=1&limit=20 → Post[]
POST   /api/v1/posts             { text, images[] } → Post
GET    /api/v1/posts/{id}        → Post (с комментариями)
DELETE /api/v1/posts/{id}        → 204
POST   /api/v1/posts/{id}/like   → 200
DELETE /api/v1/posts/{id}/like   → 204
GET    /api/v1/posts/{id}/comments → Comment[]
POST   /api/v1/posts/{id}/comments { text } → Comment
```

## Тренировки
```
GET    /api/v1/workouts           ?page=1&limit=20 → Workout[]
POST   /api/v1/workouts           { title, type, date, duration } → Workout
GET    /api/v1/workouts/{id}      → Workout (с упражнениями)
PUT    /api/v1/workouts/{id}      → Workout
DELETE /api/v1/workouts/{id}      → 204
GET    /api/v1/workouts/stats     ?period=week|month|year → Stats
```

## Музыка
```
GET    /api/v1/music/tracks       ?page=1&limit=50 → AudioTrack[]
GET    /api/v1/music/tracks/{id}  → AudioTrack
GET    /api/v1/music/playlists    → Playlist[]
POST   /api/v1/music/playlists    { name } → Playlist
GET    /api/v1/music/playlists/{id} → Playlist (с треками)
POST   /api/v1/music/playlists/{id}/tracks { track_id } → 200
DELETE /api/v1/music/playlists/{id}/tracks/{id} → 204
GET    /api/v1/music/stream/{id}  → audio/octet-stream
```

## Видео
```
GET    /api/v1/video              ?page=1&limit=20 → Video[]
POST   /api/v1/video              (multipart) → Video
GET    /api/v1/video/{id}         → Video
DELETE /api/v1/video/{id}         → 204
GET    /api/v1/video/stream/{id}  → video/mp4
```

## Трекинг (карты)
```
GET    /api/v1/tracks             ?page=1&limit=20 → Track[]
POST   /api/v1/tracks             { title, geojson } → Track
GET    /api/v1/tracks/{id}        → Track (с GeoJSON)
DELETE /api/v1/tracks/{id}        → 204
GET    /api/v1/tracks/stats       ?period=week|month|year → TrackStats
```
