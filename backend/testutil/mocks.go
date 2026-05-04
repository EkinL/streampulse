package testutil

import (
	"context"
	"sync"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

// MockUserRepo is a mock implementation of domain.UserRepository
type MockUserRepo struct {
	mu    sync.RWMutex
	users map[uuid.UUID]*domain.User
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
	return s, nil
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
			return nil
		}
	}
	return domain.ErrNotFound
}
