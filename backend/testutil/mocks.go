package testutil

import (
	"context"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

// Garde-fou de compilation : si domain.UserRepository gagne une methode,
// c'est ici que ca casse, et pas au milieu d'un fichier de test.
var _ domain.UserRepository = (*MockUserRepo)(nil)

// MockUserRepo is a mock implementation of domain.UserRepository
type MockUserRepo struct {
	mu      sync.RWMutex
	users   map[uuid.UUID]*domain.User
	byEmail map[string]*domain.User
}

func NewMockUserRepo() *MockUserRepo {
	return &MockUserRepo{
		users:   make(map[uuid.UUID]*domain.User),
		byEmail: make(map[string]*domain.User),
	}
}

func (m *MockUserRepo) Create(_ context.Context, user *domain.User) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, exists := m.byEmail[user.Email]; exists {
		return domain.ErrAlreadyExists
	}
	m.users[user.ID] = user
	m.byEmail[user.Email] = user
	return nil
}

func (m *MockUserRepo) FindByEmail(_ context.Context, email string) (*domain.User, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	u, ok := m.byEmail[email]
	if !ok {
		return nil, domain.ErrNotFound
	}
	return u, nil
}

func (m *MockUserRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	u, ok := m.users[id]
	if !ok {
		return nil, domain.ErrNotFound
	}
	return u, nil
}

func (m *MockUserRepo) FindByProviderSubject(_ context.Context, provider, subject string) (*domain.User, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, u := range m.users {
		if u.AuthProvider == provider && u.ProviderSubject == subject && subject != "" {
			return u, nil
		}
	}
	return nil, domain.ErrNotFound
}

func (m *MockUserRepo) LinkProviderSubject(_ context.Context, id uuid.UUID, provider, subject string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	u, ok := m.users[id]
	if !ok {
		return domain.ErrNotFound
	}
	for _, other := range m.users {
		if other.ID != id && other.AuthProvider == provider && other.ProviderSubject == subject {
			return domain.ErrAlreadyExists
		}
	}
	u.AuthProvider = provider
	u.ProviderSubject = subject
	return nil
}

func (m *MockUserRepo) List(_ context.Context, page, perPage int) ([]domain.User, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var all []domain.User
	for _, u := range m.users {
		all = append(all, *u)
	}
	total := len(all)
	start := (page - 1) * perPage
	if start >= total {
		return nil, total, nil
	}
	end := start + perPage
	if end > total {
		end = total
	}
	return all[start:end], total, nil
}

func (m *MockUserRepo) UpdateRole(_ context.Context, id uuid.UUID, role domain.Role) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	u, ok := m.users[id]
	if !ok {
		return domain.ErrNotFound
	}
	u.Role = role
	return nil
}

func (m *MockUserRepo) UpdateProfile(_ context.Context, id uuid.UUID, email, username string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	u, ok := m.users[id]
	if !ok {
		return domain.ErrNotFound
	}
	if existing, taken := m.byEmail[email]; taken && existing.ID != id {
		return domain.ErrAlreadyExists
	}
	delete(m.byEmail, u.Email)
	u.Email = email
	u.Username = username
	m.byEmail[email] = u
	return nil
}

func (m *MockUserRepo) Delete(_ context.Context, id uuid.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	u, ok := m.users[id]
	if !ok {
		return domain.ErrNotFound
	}
	delete(m.users, id)
	delete(m.byEmail, u.Email)
	return nil
}

// Garde-fou de compilation : si domain.StreamRepository gagne une methode,
// c'est ici que ca casse, et pas au milieu d'un fichier de test.
var _ domain.StreamRepository = (*MockStreamRepo)(nil)

// MockStreamRepo is a mock implementation of domain.StreamRepository
type MockStreamRepo struct {
	mu      sync.RWMutex
	streams map[uuid.UUID]*domain.Stream
}

func NewMockStreamRepo() *MockStreamRepo {
	return &MockStreamRepo{streams: make(map[uuid.UUID]*domain.Stream)}
}

func (m *MockStreamRepo) Create(_ context.Context, stream *domain.Stream) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if stream.ID == uuid.Nil {
		stream.ID = uuid.New()
	}
	m.streams[stream.ID] = stream
	return nil
}

func (m *MockStreamRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.Stream, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	s, ok := m.streams[id]
	if !ok {
		return nil, domain.ErrNotFound
	}
	// Copie, comme une ligne lue en base : StreamService.GetStream ecrit
	// ListenerCount sur le resultat, et des lectures concurrentes ne doivent
	// pas se partager le meme pointeur.
	cp := *s
	return &cp, nil
}

func (m *MockStreamRepo) List(_ context.Context, page, perPage int) ([]domain.Stream, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var all []domain.Stream
	for _, s := range m.streams {
		all = append(all, *s)
	}
	total := len(all)
	start := (page - 1) * perPage
	if start >= total {
		return nil, total, nil
	}
	end := start + perPage
	if end > total {
		end = total
	}
	return all[start:end], total, nil
}

func (m *MockStreamRepo) Update(_ context.Context, stream *domain.Stream) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	existing, ok := m.streams[stream.ID]
	if !ok {
		return domain.ErrNotFound
	}
	existing.Title = stream.Title
	existing.Description = stream.Description
	existing.UpdatedAt = time.Now().UTC()
	return nil
}

func (m *MockStreamRepo) UpdateStatus(_ context.Context, id uuid.UUID, status domain.StreamStatus) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.streams[id]
	if !ok {
		return domain.ErrNotFound
	}
	s.Status = status
	return nil
}

func (m *MockStreamRepo) EndLiveStreams(_ context.Context) (int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	n := 0
	for _, s := range m.streams {
		if s.Status == domain.StreamStatusLive {
			s.Status = domain.StreamStatusEnded
			s.ListenerCount = 0
			n++
		}
	}
	return n, nil
}

func (m *MockStreamRepo) UpdateListenerCount(_ context.Context, id uuid.UUID, count int) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.streams[id]
	if !ok {
		return domain.ErrNotFound
	}
	s.ListenerCount = count
	return nil
}

func (m *MockStreamRepo) ListByOwner(_ context.Context, ownerID uuid.UUID) ([]domain.Stream, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var out []domain.Stream
	for _, s := range m.streams {
		if s.OwnerID == ownerID {
			out = append(out, *s)
		}
	}
	return out, nil
}

func (m *MockStreamRepo) Delete(_ context.Context, id uuid.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.streams[id]; !ok {
		return domain.ErrNotFound
	}
	delete(m.streams, id)
	return nil
}

// MockRefreshTokenRepo is a mock implementation of domain.RefreshTokenRepository
type MockRefreshTokenRepo struct {
	mu     sync.RWMutex
	tokens map[string]uuid.UUID
}

func NewMockRefreshTokenRepo() *MockRefreshTokenRepo {
	return &MockRefreshTokenRepo{tokens: make(map[string]uuid.UUID)}
}

func (m *MockRefreshTokenRepo) Store(_ context.Context, userID uuid.UUID, tokenHash string, _ interface{}) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.tokens[tokenHash] = userID
	return nil
}

func (m *MockRefreshTokenRepo) FindByHash(_ context.Context, tokenHash string) (uuid.UUID, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	uid, ok := m.tokens[tokenHash]
	if !ok {
		return uuid.Nil, domain.ErrNotFound
	}
	return uid, nil
}

func (m *MockRefreshTokenRepo) DeleteByUserID(_ context.Context, userID uuid.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for hash, uid := range m.tokens {
		if uid == userID {
			delete(m.tokens, hash)
		}
	}
	return nil
}

func (m *MockRefreshTokenRepo) DeleteExpired(_ context.Context) error {
	return nil
}

// MockPlaylistRepo is a mock implementation of domain.PlaylistRepository
type MockPlaylistRepo struct {
	mu        sync.RWMutex
	playlists map[uuid.UUID]*domain.Playlist
}

var _ domain.PlaylistRepository = (*MockPlaylistRepo)(nil)

func NewMockPlaylistRepo() *MockPlaylistRepo {
	return &MockPlaylistRepo{playlists: make(map[uuid.UUID]*domain.Playlist)}
}

func (m *MockPlaylistRepo) Create(_ context.Context, playlist *domain.Playlist) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if playlist.ID == uuid.Nil {
		playlist.ID = uuid.New()
	}
	m.playlists[playlist.ID] = playlist
	return nil
}

func (m *MockPlaylistRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.Playlist, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	p, ok := m.playlists[id]
	if !ok {
		return nil, domain.ErrNotFound
	}
	return p, nil
}

func (m *MockPlaylistRepo) ListByOwner(_ context.Context, ownerID uuid.UUID, page, perPage int) ([]domain.Playlist, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var owned []domain.Playlist
	for _, p := range m.playlists {
		if p.OwnerID == ownerID {
			owned = append(owned, *p)
		}
	}
	total := len(owned)
	start := (page - 1) * perPage
	if start >= total {
		return nil, total, nil
	}
	end := start + perPage
	if end > total {
		end = total
	}
	return owned[start:end], total, nil
}

func (m *MockPlaylistRepo) ListPublic(_ context.Context, page, perPage int) ([]domain.Playlist, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var pub []domain.Playlist
	for _, p := range m.playlists {
		if p.IsPublic {
			pub = append(pub, *p)
		}
	}
	total := len(pub)
	start := (page - 1) * perPage
	if start >= total {
		return nil, total, nil
	}
	end := start + perPage
	if end > total {
		end = total
	}
	return pub[start:end], total, nil
}

func (m *MockPlaylistRepo) Update(_ context.Context, playlist *domain.Playlist) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.playlists[playlist.ID]; !ok {
		return domain.ErrNotFound
	}
	m.playlists[playlist.ID] = playlist
	return nil
}

func (m *MockPlaylistRepo) Delete(_ context.Context, id uuid.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.playlists[id]; !ok {
		return domain.ErrNotFound
	}
	delete(m.playlists, id)
	return nil
}

func (m *MockPlaylistRepo) AddTrack(_ context.Context, playlistID uuid.UUID, track *domain.Track) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.playlists[playlistID]
	if !ok {
		return domain.ErrNotFound
	}
	if track.ID == uuid.Nil {
		track.ID = uuid.New()
	}
	track.Position = len(p.Tracks)
	p.Tracks = append(p.Tracks, *track)
	return nil
}

func (m *MockPlaylistRepo) RemoveTrack(_ context.Context, playlistID, trackID uuid.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.playlists[playlistID]
	if !ok {
		return domain.ErrNotFound
	}
	for i, t := range p.Tracks {
		if t.ID == trackID {
			p.Tracks = append(p.Tracks[:i], p.Tracks[i+1:]...)
			// Mirror the real repo: positions are compacted after a removal.
			for j := range p.Tracks {
				p.Tracks[j].Position = j
			}
			return nil
		}
	}
	return domain.ErrNotFound
}

func (m *MockPlaylistRepo) ReorderTracks(_ context.Context, playlistID uuid.UUID, trackIDs []uuid.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.playlists[playlistID]
	if !ok {
		return domain.ErrNotFound
	}
	if len(trackIDs) != len(p.Tracks) {
		return domain.ErrInvalidInput
	}
	byID := make(map[uuid.UUID]domain.Track, len(p.Tracks))
	for _, t := range p.Tracks {
		byID[t.ID] = t
	}
	reordered := make([]domain.Track, 0, len(trackIDs))
	for i, id := range trackIDs {
		t, ok := byID[id]
		if !ok {
			return domain.ErrNotFound
		}
		t.Position = i
		reordered = append(reordered, t)
	}
	p.Tracks = reordered
	return nil
}

// MockMusicRepo is an in-memory implementation of domain.MusicRepository.
var _ domain.MusicRepository = (*MockMusicRepo)(nil)

type MockMusicRepo struct {
	mu    sync.RWMutex
	items []*domain.Music
}

func NewMockMusicRepo() *MockMusicRepo {
	return &MockMusicRepo{}
}

func (m *MockMusicRepo) Create(_ context.Context, music *domain.Music) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if music.ID == uuid.Nil {
		music.ID = uuid.New()
	}
	music.CreatedAt = time.Now().UTC()
	cp := *music
	m.items = append(m.items, &cp)
	return nil
}

func (m *MockMusicRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.Music, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, it := range m.items {
		if it.ID == id {
			cp := *it
			return &cp, nil
		}
	}
	return nil, domain.ErrNotFound
}

func (m *MockMusicRepo) List(_ context.Context, page, perPage int) ([]domain.Music, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.filter(func(*domain.Music) bool { return true }, page, perPage)
}

// Search imite plainto_tsquery de facon volontairement simple : un mot de la
// requete present dans le titre ou l'artiste suffit.
func (m *MockMusicRepo) Search(_ context.Context, query string, page, perPage int) ([]domain.Music, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	words := strings.Fields(strings.ToLower(query))
	return m.filter(func(it *domain.Music) bool {
		haystack := strings.ToLower(it.Title + " " + it.Artist)
		for _, w := range words {
			if strings.Contains(haystack, w) {
				return true
			}
		}
		return false
	}, page, perPage)
}

func (m *MockMusicRepo) ListByUploader(_ context.Context, uploaderID uuid.UUID, page, perPage int) ([]domain.Music, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.filter(func(it *domain.Music) bool { return it.UploadedBy == uploaderID }, page, perPage)
}

func (m *MockMusicRepo) AllByUploader(_ context.Context, uploaderID uuid.UUID) ([]domain.Music, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var out []domain.Music
	for _, it := range m.items {
		if it.UploadedBy == uploaderID {
			out = append(out, *it)
		}
	}
	return out, nil
}

func (m *MockMusicRepo) Update(_ context.Context, music *domain.Music) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, it := range m.items {
		if it.ID == music.ID {
			it.Title, it.Artist, it.Album, it.CoverURL = music.Title, music.Artist, music.Album, music.CoverURL
			return nil
		}
	}
	return domain.ErrNotFound
}

func (m *MockMusicRepo) Delete(_ context.Context, id uuid.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i, it := range m.items {
		if it.ID == id {
			m.items = append(m.items[:i], m.items[i+1:]...)
			return nil
		}
	}
	return domain.ErrNotFound
}

func (m *MockMusicRepo) filter(keep func(*domain.Music) bool, page, perPage int) ([]domain.Music, int, error) {
	var all []domain.Music
	for _, it := range m.items {
		if keep(it) {
			all = append(all, *it)
		}
	}
	total := len(all)
	start := (page - 1) * perPage
	if start >= total {
		return nil, total, nil
	}
	end := start + perPage
	if end > total {
		end = total
	}
	return all[start:end], total, nil
}

// MockFeedbackRepo is a mock implementation of domain.FeedbackRepository
type MockFeedbackRepo struct {
	mu    sync.RWMutex
	items map[uuid.UUID]*domain.Feedback
}

var _ domain.FeedbackRepository = (*MockFeedbackRepo)(nil)

func NewMockFeedbackRepo() *MockFeedbackRepo {
	return &MockFeedbackRepo{items: make(map[uuid.UUID]*domain.Feedback)}
}

func (m *MockFeedbackRepo) Create(_ context.Context, feedback *domain.Feedback) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if feedback.ID == uuid.Nil {
		feedback.ID = uuid.New()
	}
	feedback.Status = domain.FeedbackStatusNew
	m.items[feedback.ID] = feedback
	return nil
}

func (m *MockFeedbackRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.Feedback, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	f, ok := m.items[id]
	if !ok {
		return nil, domain.ErrNotFound
	}
	return f, nil
}

func (m *MockFeedbackRepo) List(_ context.Context, status domain.FeedbackStatus, page, perPage int) ([]domain.Feedback, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var matched []domain.Feedback
	for _, f := range m.items {
		if status == "" || f.Status == status {
			matched = append(matched, *f)
		}
	}
	total := len(matched)
	start := (page - 1) * perPage
	if start >= total {
		return nil, total, nil
	}
	end := start + perPage
	if end > total {
		end = total
	}
	return matched[start:end], total, nil
}

func (m *MockFeedbackRepo) UpdateStatus(_ context.Context, id uuid.UUID, status domain.FeedbackStatus) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	f, ok := m.items[id]
	if !ok {
		return domain.ErrNotFound
	}
	f.Status = status
	return nil
}
