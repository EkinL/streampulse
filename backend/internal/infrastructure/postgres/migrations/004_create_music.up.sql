CREATE TABLE music (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    artist VARCHAR(255) NOT NULL DEFAULT '',
    album VARCHAR(255) NOT NULL DEFAULT '',
    duration INT NOT NULL DEFAULT 0,
    url TEXT NOT NULL,
    cover_url TEXT,
    uploaded_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_music_uploaded ON music(uploaded_by);
CREATE INDEX idx_music_created ON music(created_at DESC);
CREATE INDEX idx_music_search_title ON music USING gin(to_tsvector('english', title));
CREATE INDEX idx_music_search_artist ON music USING gin(to_tsvector('english', artist));

ALTER TABLE tracks ADD COLUMN music_id UUID REFERENCES music(id) ON DELETE SET NULL;
