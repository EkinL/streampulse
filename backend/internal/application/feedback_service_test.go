package application_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/testutil"
)

func newFeedbackService() (*application.FeedbackService, *testutil.MockFeedbackRepo) {
	repo := testutil.NewMockFeedbackRepo()
	svc := application.NewFeedbackService(repo)
	return svc, repo
}

func TestFeedbackService_Submit(t *testing.T) {
	svc, _ := newFeedbackService()
	ctx := context.Background()
	userID := uuid.New()

	f, err := svc.Submit(ctx, application.SubmitFeedbackInput{
		UserID:     userID,
		Type:       domain.FeedbackTypeBug,
		Message:    "Le lecteur coupe le son apres 30 secondes.",
		AppVersion: "1.0.0",
		Platform:   "android",
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if f.ID == uuid.Nil {
		t.Fatal("expected an ID to be assigned")
	}
	if f.UserID != userID {
		t.Fatalf("expected user ID %s, got %s", userID, f.UserID)
	}
	if f.Status != domain.FeedbackStatusNew {
		t.Fatalf("expected status %q, got %q", domain.FeedbackStatusNew, f.Status)
	}
}

func TestFeedbackService_Submit_InvalidType(t *testing.T) {
	svc, _ := newFeedbackService()
	_, err := svc.Submit(context.Background(), application.SubmitFeedbackInput{
		UserID:  uuid.New(),
		Type:    domain.FeedbackType("not-a-type"),
		Message: "peu importe",
	})
	if !errors.Is(err, domain.ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestFeedbackService_Submit_EmptyMessage(t *testing.T) {
	svc, _ := newFeedbackService()
	_, err := svc.Submit(context.Background(), application.SubmitFeedbackInput{
		UserID: uuid.New(),
		Type:   domain.FeedbackTypeSuggestion,
	})
	if !errors.Is(err, domain.ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestFeedbackService_Submit_MessageTooLong(t *testing.T) {
	svc, _ := newFeedbackService()
	_, err := svc.Submit(context.Background(), application.SubmitFeedbackInput{
		UserID:  uuid.New(),
		Type:    domain.FeedbackTypeOther,
		Message: strings.Repeat("a", 4001),
	})
	if !errors.Is(err, domain.ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestFeedbackService_List_FiltersByStatus(t *testing.T) {
	svc, repo := newFeedbackService()
	ctx := context.Background()

	f1, _ := svc.Submit(ctx, application.SubmitFeedbackInput{UserID: uuid.New(), Type: domain.FeedbackTypeBug, Message: "un"})
	_, _ = svc.Submit(ctx, application.SubmitFeedbackInput{UserID: uuid.New(), Type: domain.FeedbackTypeBug, Message: "deux"})
	if err := repo.UpdateStatus(ctx, f1.ID, domain.FeedbackStatusResolved); err != nil {
		t.Fatalf("setup: %v", err)
	}

	items, total, err := svc.List(ctx, domain.FeedbackStatusResolved, 1, 20)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if total != 1 || len(items) != 1 || items[0].ID != f1.ID {
		t.Fatalf("expected exactly f1 resolved, got %+v (total %d)", items, total)
	}
}

func TestFeedbackService_List_InvalidStatus(t *testing.T) {
	svc, _ := newFeedbackService()
	_, _, err := svc.List(context.Background(), domain.FeedbackStatus("bogus"), 1, 20)
	if !errors.Is(err, domain.ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestFeedbackService_UpdateStatus(t *testing.T) {
	svc, _ := newFeedbackService()
	ctx := context.Background()

	f, err := svc.Submit(ctx, application.SubmitFeedbackInput{UserID: uuid.New(), Type: domain.FeedbackTypeBug, Message: "un bug"})
	if err != nil {
		t.Fatalf("setup: %v", err)
	}

	if err := svc.UpdateStatus(ctx, f.ID, domain.FeedbackStatusInProgress); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	items, _, err := svc.List(ctx, domain.FeedbackStatusInProgress, 1, 20)
	if err != nil || len(items) != 1 {
		t.Fatalf("expected feedback to now be in_progress, got items=%+v err=%v", items, err)
	}
}

func TestFeedbackService_UpdateStatus_InvalidStatus(t *testing.T) {
	svc, _ := newFeedbackService()
	err := svc.UpdateStatus(context.Background(), uuid.New(), domain.FeedbackStatus("bogus"))
	if !errors.Is(err, domain.ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput, got %v", err)
	}
}

func TestFeedbackService_UpdateStatus_NotFound(t *testing.T) {
	svc, _ := newFeedbackService()
	err := svc.UpdateStatus(context.Background(), uuid.New(), domain.FeedbackStatusResolved)
	if !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}
