package application

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
)

type StreamService struct {
	streamRepo domain.StreamRepository
	hub        *streaming.Hub
}

func NewStreamService(streamRepo domain.StreamRepository, hub *streaming.Hub) *StreamService {
	return &StreamService{
		streamRepo: streamRepo,
		hub:        hub,
	}
}

type CreateStreamInput struct {
	Title       string
	Description string
	Format      string
	OwnerID     uuid.UUID
}

func (s *StreamService) CreateStream(ctx context.Context, input CreateStreamInput) (*domain.Stream, error) {
	if input.Title == "" {
		return nil, fmt.Errorf("stream: create: title is required: %w", domain.ErrInvalidInput)
	}
	if input.Format == "" {
		input.Format = "mp3"
	}

	stream := &domain.Stream{
		Title:       input.Title,
		Description: input.Description,
		OwnerID:     input.OwnerID,
		Format:      input.Format,
	}

	if err := s.streamRepo.Create(ctx, stream); err != nil {
		return nil, fmt.Errorf("stream: create: %w", err)
	}
	return stream, nil
}

func (s *StreamService) GetStream(ctx context.Context, id uuid.UUID) (*domain.Stream, error) {
	stream, err := s.streamRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("stream: get: %w", err)
	}
	// Update listener count from hub
	stream.ListenerCount = s.hub.ListenerCount(id)
	return stream, nil
}

func (s *StreamService) ListStreams(ctx context.Context, page, perPage int) ([]domain.Stream, int, error) {
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 {
		perPage = 20
	}
	streams, total, err := s.streamRepo.List(ctx, page, perPage)
	if err != nil {
		return nil, 0, fmt.Errorf("stream: list: %w", err)
	}

	// Update listener counts from hub
	for i := range streams {
		streams[i].ListenerCount = s.hub.ListenerCount(streams[i].ID)
	}
	return streams, total, nil
}

func (s *StreamService) UpdateStream(ctx context.Context, streamID, ownerID uuid.UUID, title, description string) (*domain.Stream, error) {
	stream, err := s.streamRepo.FindByID(ctx, streamID)
	if err != nil {
		return nil, fmt.Errorf("stream: update: %w", err)
	}
	if stream.OwnerID != ownerID {
		return nil, fmt.Errorf("stream: update: %w", domain.ErrNotOwner)
	}

	stream.Title = title
	stream.Description = description

	if err := s.streamRepo.Update(ctx, stream); err != nil {
		return nil, fmt.Errorf("stream: update: %w", err)
	}
	return stream, nil
}

func (s *StreamService) StartStream(ctx context.Context, streamID, ownerID uuid.UUID) error {
	stream, err := s.streamRepo.FindByID(ctx, streamID)
	if err != nil {
		return fmt.Errorf("stream: start: %w", err)
	}
	if stream.OwnerID != ownerID {
		return fmt.Errorf("stream: start: %w", domain.ErrNotOwner)
	}
	if stream.Status == domain.StreamStatusLive {
		return fmt.Errorf("stream: start: %w", domain.ErrStreamAlreadyLive)
	}

	if err := s.streamRepo.UpdateStatus(ctx, streamID, domain.StreamStatusLive); err != nil {
		return fmt.Errorf("stream: start: %w", err)
	}
	return nil
}

func (s *StreamService) StopStream(ctx context.Context, streamID, ownerID uuid.UUID) error {
	stream, err := s.streamRepo.FindByID(ctx, streamID)
	if err != nil {
		return fmt.Errorf("stream: stop: %w", err)
	}
	if stream.OwnerID != ownerID {
		return fmt.Errorf("stream: stop: %w", domain.ErrNotOwner)
	}

	s.hub.CloseStream(streamID)

	if err := s.streamRepo.UpdateStatus(ctx, streamID, domain.StreamStatusEnded); err != nil {
		return fmt.Errorf("stream: stop: %w", err)
	}
	if err := s.streamRepo.UpdateListenerCount(ctx, streamID, 0); err != nil {
		return fmt.Errorf("stream: stop: update listener count: %w", err)
	}
	return nil
}

// EndOrphanedLiveStreams passe en "ended" tous les flux encore "live" et
// rend leur nombre. A appeler au demarrage : aucun diffuseur n'est connecte
// a ce moment-la, ces directs sont des restes d'un arret du serveur en
// plein live. Sans ce nettoyage ils resteraient affiches live, muets.
func (s *StreamService) EndOrphanedLiveStreams(ctx context.Context) (int, error) {
	n, err := s.streamRepo.EndLiveStreams(ctx)
	if err != nil {
		return 0, fmt.Errorf("stream: end orphaned live streams: %w", err)
	}
	return n, nil
}

func (s *StreamService) Hub() *streaming.Hub {
	return s.hub
}
