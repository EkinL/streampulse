package testutil

import (
	"time"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

func NewTestUser(role domain.Role) *domain.User {
	return &domain.User{
		ID:              uuid.New(),
		Email:           "test-" + uuid.New().String()[:8] + "@example.com",
		Username:        "testuser",
		PasswordHash:    "$2a$12$dummyhashfortest000000000000000000000000000000000000",
		Role:            role,
		TermsAcceptedAt: time.Now().UTC(),
		CreatedAt:       time.Now().UTC(),
		UpdatedAt:       time.Now().UTC(),
	}
}

func NewTestStream(ownerID uuid.UUID) *domain.Stream {
	return &domain.Stream{
		ID:          uuid.New(),
		Title:       "Test Stream",
		Description: "A test stream",
		OwnerID:     ownerID,
		Status:      domain.StreamStatusIdle,
		Format:      "mp3",
		CreatedAt:   time.Now().UTC(),
		UpdatedAt:   time.Now().UTC(),
	}
}

func NewTestPlaylist(ownerID uuid.UUID) *domain.Playlist {
	return &domain.Playlist{
		ID:        uuid.New(),
		Name:      "Test Playlist",
		OwnerID:   ownerID,
		IsPublic:  false,
		CreatedAt: time.Now().UTC(),
		UpdatedAt: time.Now().UTC(),
	}
}

func NewTestTrack() *domain.Track {
	return &domain.Track{
		ID:       uuid.New(),
		Title:    "Test Track",
		URL:      "https://example.com/audio.mp3",
		Duration: 180,
		Position: 0,
	}
}
