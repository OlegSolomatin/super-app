# База данных Super-App

## Схема связей

```
users ──┬── posts ──┬── likes
        │           └── comments
        │
        ├── workouts ──┬── workout_exercises
        │
        ├── tracks
        │
        ├── playlists ──┬── playlist_tracks ──┬── audio_tracks
        │
        └── videos
```

## Таблицы

### users — пользователи
```sql
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    username      VARCHAR(100) UNIQUE NOT NULL,
    avatar_url    TEXT,
    bio           TEXT,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);
```

### posts — посты (социальная сеть)
```sql
CREATE TABLE posts (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    text       TEXT NOT NULL,
    images     TEXT[] DEFAULT '{}',
    video_url  TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### likes — лайки
```sql
CREATE TABLE likes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(post_id, user_id)
);
```

### comments — комментарии
```sql
CREATE TABLE comments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    text       TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### workouts — тренировки
```sql
CREATE TABLE workouts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    title       VARCHAR(200) NOT NULL,
    type        VARCHAR(50) NOT NULL,       -- running, gym, yoga, cycling
    date        DATE NOT NULL,
    duration    INTEGER NOT NULL,            -- секунды
    calories    INTEGER,
    notes       TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### workout_exercises — упражнения
```sql
CREATE TABLE workout_exercises (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_id  UUID REFERENCES workouts(id) ON DELETE CASCADE,
    name        VARCHAR(200) NOT NULL,
    sets        INTEGER DEFAULT 0,
    reps        INTEGER DEFAULT 0,
    weight      DECIMAL(8,2) DEFAULT 0,     -- кг
    duration    INTEGER DEFAULT 0           -- секунды (кардио)
);
```

### tracks — GPS маршруты
```sql
CREATE TABLE tracks (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID REFERENCES users(id) ON DELETE CASCADE,
    title         VARCHAR(200),
    date          DATE NOT NULL,
    route_geojson JSONB NOT NULL,            -- GeoJSON LineString
    distance      DECIMAL(10,2) DEFAULT 0,   -- метры
    duration      INTEGER DEFAULT 0,         -- секунды
    avg_speed     DECIMAL(5,2) DEFAULT 0,    -- км/ч
    elevation_gain DECIMAL(8,2) DEFAULT 0,   -- метры
    created_at    TIMESTAMPTZ DEFAULT NOW()
);
```

### audio_tracks — музыкальные треки
```sql
CREATE TABLE audio_tracks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title       VARCHAR(300) NOT NULL,
    artist      VARCHAR(300) DEFAULT 'Unknown',
    album       VARCHAR(300),
    duration    INTEGER NOT NULL,            -- секунды
    file_url    TEXT NOT NULL,
    cover_url   TEXT,
    file_size   BIGINT,                      -- байты
    format      VARCHAR(10) DEFAULT 'mp3',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### playlists — плейлисты
```sql
CREATE TABLE playlists (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    name        VARCHAR(200) NOT NULL,
    cover_url   TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### playlist_tracks — треки в плейлисте
```sql
CREATE TABLE playlist_tracks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    playlist_id UUID REFERENCES playlists(id) ON DELETE CASCADE,
    track_id    UUID REFERENCES audio_tracks(id) ON DELETE CASCADE,
    position    INTEGER NOT NULL,
    UNIQUE(playlist_id, position)
);
```

### videos — видео
```sql
CREATE TABLE videos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    title       VARCHAR(300) NOT NULL,
    description TEXT,
    file_url    TEXT NOT NULL,
    thumbnail   TEXT,
    duration    INTEGER NOT NULL,            -- секунды
    file_size   BIGINT,
    format      VARCHAR(10) DEFAULT 'mp4',
    views       INTEGER DEFAULT 0,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
```
