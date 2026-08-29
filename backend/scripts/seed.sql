-- Dev-only fixtures. Both accounts share the password `admin123`
-- (bcrypt cost 12). Fictional addresses on purpose: no real person's data
-- belongs in the repository (docs/rgpd.md).
--   admin@streampulse.io       / admin123  -> admin
--   broadcaster@streampulse.io / admin123  -> broadcaster
-- Upsert on purpose: re-running the seed resets the password if the row exists.
INSERT INTO users (id, email, username, password_hash, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'admin@streampulse.io', 'admin',
   '$2a$12$w3smmWvQLDjWWUZIQ/2XxO9KDnW1.4JbKkFZHgOlkdHB3ycgO9PFO', 'admin'),
  ('00000000-0000-0000-0000-000000000002', 'broadcaster@streampulse.io', 'broadcaster',
   '$2a$12$w3smmWvQLDjWWUZIQ/2XxO9KDnW1.4JbKkFZHgOlkdHB3ycgO9PFO', 'broadcaster')
ON CONFLICT (email) DO UPDATE
  SET password_hash = EXCLUDED.password_hash, role = EXCLUDED.role;

-- Create some test streams
INSERT INTO streams (id, title, description, owner_id, status, format) VALUES
  (uuid_generate_v4(), 'Jazz Lounge', 'Smooth jazz for late nights', '00000000-0000-0000-0000-000000000002', 'idle', 'mp3'),
  (uuid_generate_v4(), 'Lo-Fi Beats', 'Chill beats to study/relax to', '00000000-0000-0000-0000-000000000002', 'idle', 'mp3'),
  (uuid_generate_v4(), 'Live Podcast', 'Weekly tech discussions', '00000000-0000-0000-0000-000000000002', 'idle', 'mp3')
ON CONFLICT DO NOTHING;
