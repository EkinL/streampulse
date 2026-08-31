-- Seed music tracks (using the broadcaster user)
INSERT INTO music (title, artist, album, duration, url, uploaded_by) VALUES
  ('Midnight Drive', 'Synthwave FM', 'Neon Nights', 237, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3', '00000000-0000-0000-0000-000000000002'),
  ('Chill Lo-Fi Study', 'Beats Lab', 'Study Sessions', 185, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3', '00000000-0000-0000-0000-000000000002'),
  ('Electric Dreams', 'Retro Pulse', 'Synthwave Vol.1', 312, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3', '00000000-0000-0000-0000-000000000002'),
  ('Deep House Groove', 'DJ Horizon', 'Club Sessions', 268, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3', '00000000-0000-0000-0000-000000000002'),
  ('Acoustic Sunset', 'Sierra Sky', 'Golden Hour', 195, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3', '00000000-0000-0000-0000-000000000002'),
  ('Jazz Cafe Vibes', 'Blue Note Trio', 'Late Night Jazz', 224, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3', '00000000-0000-0000-0000-000000000002'),
  ('Ambient Waves', 'Cloud Atlas', 'Dreamscapes', 340, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3', '00000000-0000-0000-0000-000000000002'),
  ('Techno Underground', 'Berlin Bass', 'Warehouse Nights', 290, 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3', '00000000-0000-0000-0000-000000000002')
ON CONFLICT DO NOTHING;
