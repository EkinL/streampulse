package application

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

type PlaylistService struct {
	playlistRepo domain.PlaylistRepository
}

func NewPlaylistService(playlistRepo domain.PlaylistRepository) *PlaylistService {
	return &PlaylistService{playlistRepo: playlistRepo}
}

type CreatePlaylistInput struct {
	Name     string
	OwnerID  uuid.UUID
	IsPublic bool
}

type UpdatePlaylistInput struct {
	ID       uuid.UUID
	Name     string
	IsPublic bool
	OwnerID  uuid.UUID
}

type AddTrackInput struct {
	PlaylistID uuid.UUID
	OwnerID    uuid.UUID
	Title      string
	URL        string
	Duration   int
}

func (s *PlaylistService) CreatePlaylist(ctx context.Context, input CreatePlaylistInput) (*domain.Playlist, error) {
	if input.Name == "" {
		return nil, fmt.Errorf("playlist: create: name is required: %w", domain.ErrInvalidInput)
	}

	playlist := &domain.Playlist{
		Name:     input.Name,
		OwnerID:  input.OwnerID,
		IsPublic: input.IsPublic,
	}

	if err := s.playlistRepo.Create(ctx, playlist); err != nil {
		return nil, fmt.Errorf("playlist: create: %w", err)
	}
	return playlist, nil
}

func (s *PlaylistService) GetPlaylist(ctx context.Context, id uuid.UUID) (*domain.Playlist, error) {
	playlist, err := s.playlistRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("playlist: get: %w", err)
	}
	return playlist, nil
}

func (s *PlaylistService) ListPlaylists(ctx context.Context, ownerID uuid.UUID, page, perPage int) ([]domain.Playlist, int, error) {
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 {
		perPage = 20
	}
	playlists, total, err := s.playlistRepo.ListByOwner(ctx, ownerID, page, perPage)
	if err != nil {
		return nil, 0, fmt.Errorf("playlist: list: %w", err)
	}
	return playlists, total, nil
}

func (s *PlaylistService) ListPublicPlaylists(ctx context.Context, page, perPage int) ([]domain.Playlist, int, error) {
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 {
		perPage = 20
	}
	return s.playlistRepo.ListPublic(ctx, page, perPage)
}

func (s *PlaylistService) UpdatePlaylist(ctx context.Context, input UpdatePlaylistInput) (*domain.Playlist, error) {
	playlist, err := s.playlistRepo.FindByID(ctx, input.ID)
	if err != nil {
		return nil, fmt.Errorf("playlist: update: %w", err)
	}
	if playlist.OwnerID != input.OwnerID {
		return nil, fmt.Errorf("playlist: update: %w", domain.ErrNotOwner)
	}

	playlist.Name = input.Name
	playlist.IsPublic = input.IsPublic

	if err := s.playlistRepo.Update(ctx, playlist); err != nil {
		return nil, fmt.Errorf("playlist: update: %w", err)
	}
	return playlist, nil
}

func (s *PlaylistService) DeletePlaylist(ctx context.Context, id, ownerID uuid.UUID) error {
	playlist, err := s.playlistRepo.FindByID(ctx, id)
	if err != nil {
		return fmt.Errorf("playlist: delete: %w", err)
	}
	if playlist.OwnerID != ownerID {
		return fmt.Errorf("playlist: delete: %w", domain.ErrNotOwner)
	}

	if err := s.playlistRepo.Delete(ctx, id); err != nil {
		return fmt.Errorf("playlist: delete: %w", err)
	}
	return nil
}

func (s *PlaylistService) AddTrack(ctx context.Context, input AddTrackInput) (*domain.Track, error) {
	playlist, err := s.playlistRepo.FindByID(ctx, input.PlaylistID)
	if err != nil {
		return nil, fmt.Errorf("playlist: add_track: %w", err)
	}
	if playlist.OwnerID != input.OwnerID {
		return nil, fmt.Errorf("playlist: add_track: %w", domain.ErrNotOwner)
	}

	track := &domain.Track{
		Title:    input.Title,
		URL:      input.URL,
		Duration: input.Duration,
	}

	if err := s.playlistRepo.AddTrack(ctx, input.PlaylistID, track); err != nil {
		return nil, fmt.Errorf("playlist: add_track: %w", err)
	}
	return track, nil
}

func (s *PlaylistService) RemoveTrack(ctx context.Context, playlistID, trackID, ownerID uuid.UUID) error {
	playlist, err := s.playlistRepo.FindByID(ctx, playlistID)
	if err != nil {
		return fmt.Errorf("playlist: remove_track: %w", err)
	}
	if playlist.OwnerID != ownerID {
		return fmt.Errorf("playlist: remove_track: %w", domain.ErrNotOwner)
	}

	if err := s.playlistRepo.RemoveTrack(ctx, playlistID, trackID); err != nil {
		return fmt.Errorf("playlist: remove_track: %w", err)
	}
	return nil
}
