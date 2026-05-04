CREATE TABLE music_favorites (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    music_id UUID NOT NULL REFERENCES music(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, music_id)
);
