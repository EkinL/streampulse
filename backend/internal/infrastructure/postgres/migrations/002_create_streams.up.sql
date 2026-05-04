CREATE TABLE streams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'idle',
    listener_count INT NOT NULL DEFAULT 0,
    format VARCHAR(10) NOT NULL DEFAULT 'mp3',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_streams_owner ON streams(owner_id);
CREATE INDEX idx_streams_status ON streams(status);
