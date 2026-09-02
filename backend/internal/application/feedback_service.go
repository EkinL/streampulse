package application

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

type FeedbackService struct {
	feedbackRepo domain.FeedbackRepository
}

func NewFeedbackService(feedbackRepo domain.FeedbackRepository) *FeedbackService {
	return &FeedbackService{feedbackRepo: feedbackRepo}
}

type SubmitFeedbackInput struct {
	UserID     uuid.UUID
	Type       domain.FeedbackType
	Message    string
	AppVersion string
	Platform   string
}

const feedbackMessageMaxLen = 4000

func (s *FeedbackService) Submit(ctx context.Context, input SubmitFeedbackInput) (*domain.Feedback, error) {
	if !input.Type.IsValid() {
		return nil, fmt.Errorf("feedback: submit: invalid type: %w", domain.ErrInvalidInput)
	}
	if input.Message == "" {
		return nil, fmt.Errorf("feedback: submit: message is required: %w", domain.ErrInvalidInput)
	}
	if len(input.Message) > feedbackMessageMaxLen {
		return nil, fmt.Errorf("feedback: submit: message exceeds %d characters: %w", feedbackMessageMaxLen, domain.ErrInvalidInput)
	}

	feedback := &domain.Feedback{
		UserID:     input.UserID,
		Type:       input.Type,
		Message:    input.Message,
		AppVersion: input.AppVersion,
		Platform:   input.Platform,
	}

	if err := s.feedbackRepo.Create(ctx, feedback); err != nil {
		return nil, fmt.Errorf("feedback: submit: %w", err)
	}
	return feedback, nil
}

func (s *FeedbackService) List(ctx context.Context, status domain.FeedbackStatus, page, perPage int) ([]domain.Feedback, int, error) {
	if status != "" && !status.IsValid() {
		return nil, 0, fmt.Errorf("feedback: list: invalid status: %w", domain.ErrInvalidInput)
	}
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 {
		perPage = 20
	}
	items, total, err := s.feedbackRepo.List(ctx, status, page, perPage)
	if err != nil {
		return nil, 0, fmt.Errorf("feedback: list: %w", err)
	}
	return items, total, nil
}

func (s *FeedbackService) UpdateStatus(ctx context.Context, id uuid.UUID, status domain.FeedbackStatus) error {
	if !status.IsValid() {
		return fmt.Errorf("feedback: update_status: invalid status: %w", domain.ErrInvalidInput)
	}
	if err := s.feedbackRepo.UpdateStatus(ctx, id, status); err != nil {
		return fmt.Errorf("feedback: update_status: %w", err)
	}
	return nil
}
