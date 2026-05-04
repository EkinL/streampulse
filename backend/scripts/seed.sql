-- Promote existing user to broadcaster (replace email if needed)
UPDATE users SET role = 'broadcaster' WHERE email = 'fayzerdev@gmail.com';

-- Create a second test user (admin) for testing
INSERT INTO users (id, email, username, password_hash, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'admin@streampulse.io', 'admin',
   '$2a$12$LJ3m8CqONkH1EfRhKBG7/.1rBBCfPTJR5R7YVKZ6E3tJHI5TK8Cy', 'admin')
ON CONFLICT (email) DO NOTHING;

-- Create some test streams
INSERT INTO streams (id, title, description, owner_id, status, format) VALUES
  (uuid_generate_v4(), 'Jazz Lounge', 'Smooth jazz for late nights', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com'), 'idle', 'mp3'),
  (uuid_generate_v4(), 'Lo-Fi Beats', 'Chill beats to study/relax to', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com'), 'idle', 'mp3'),
  (uuid_generate_v4(), 'Live Podcast', 'Weekly tech discussions', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com'), 'idle', 'mp3')
ON CONFLICT DO NOTHING;
