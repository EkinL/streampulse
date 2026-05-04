-- Seed music tracks (using the broadcaster user)
INSERT INTO music (title, artist, album, duration, url, uploaded_by) VALUES
  ('Midnight Drive', 'Synthwave FM', 'Neon Nights', 237, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com')),
  ('Chill Lo-Fi Study', 'Beats Lab', 'Study Sessions', 185, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com')),
  ('Electric Dreams', 'Retro Pulse', 'Synthwave Vol.1', 312, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com')),
  ('Deep House Groove', 'DJ Horizon', 'Club Sessions', 268, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com')),
  ('Acoustic Sunset', 'Sierra Sky', 'Golden Hour', 195, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com')),
  ('Jazz Cafe Vibes', 'Blue Note Trio', 'Late Night Jazz', 224, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com')),
  ('Ambient Waves', 'Cloud Atlas', 'Dreamscapes', 340, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com')),
  ('Techno Underground', 'Berlin Bass', 'Warehouse Nights', 290, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3', (SELECT id FROM users WHERE email = 'fayzerdev@gmail.com'))
ON CONFLICT DO NOTHING;
