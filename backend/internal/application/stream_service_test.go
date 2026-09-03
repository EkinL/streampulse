package application_test

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/rs/zerolog"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	"github.com/streampulse/backend/testutil"
)

func newStreamService() (*application.StreamService, *testutil.MockStreamRepo) {
	repo := testutil.NewMockStreamRepo()
	logger := zerolog.Nop()
	hub := streaming.NewHub(logger)
	svc := application.NewStreamService(repo, hub)
	return svc, repo
}

func TestStreamService_CreateStream(t *testing.T) {
	t.Run("create stream", func(t *testing.T) {
		svc, _ := newStreamService()
		ctx := context.Background()
		ownerID := uuid.New()

		stream, err := svc.CreateStream(ctx, application.CreateStreamInput{
			Title:       "My Stream",
			Description: "A cool stream",
			Format:      "mp3",
			OwnerID:     ownerID,
		})
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if stream.Title != "My Stream" {
			t.Fatalf("expected title 'My Stream', got %q", stream.Title)
		}
		if stream.OwnerID != ownerID {
			t.Fatalf("expected owner ID %s, got %s", ownerID, stream.OwnerID)
		}
		if stream.ID == uuid.Nil {
			t.Fatal("expected stream ID to be assigned")
		}
	})
}

func TestStreamService_GetStream(t *testing.T) {
	t.Run("get stream", func(t *testing.T) {
		svc, _ := newStreamService()
		ctx := context.Background()
		ownerID := uuid.New()

		created, err := svc.CreateStream(ctx, application.CreateStreamInput{
			Title:   "My Stream",
			OwnerID: ownerID,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		got, err := svc.GetStream(ctx, created.ID)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if got.Title != "My Stream" {
			t.Fatalf("expected title 'My Stream', got %q", got.Title)
		}
	})
}

func TestStreamService_ListStreams(t *testing.T) {
	t.Run("list streams", func(t *testing.T) {
		svc, _ := newStreamService()
		ctx := context.Background()
		ownerID := uuid.New()

		for i := 0; i < 3; i++ {
			_, err := svc.CreateStream(ctx, application.CreateStreamInput{
				Title:   "Stream",
				OwnerID: ownerID,
			})
			if err != nil {
				t.Fatalf("create failed: %v", err)
			}
		}

		streams, total, err := svc.ListStreams(ctx, 1, 20)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if total != 3 {
			t.Fatalf("expected total 3, got %d", total)
		}
		if len(streams) != 3 {
			t.Fatalf("expected 3 streams, got %d", len(streams))
		}
	})
}

func TestStreamService_StartStream(t *testing.T) {
	t.Run("start stream not owner error", func(t *testing.T) {
		svc, _ := newStreamService()
		ctx := context.Background()
		ownerID := uuid.New()
		otherID := uuid.New()

		stream, err := svc.CreateStream(ctx, application.CreateStreamInput{
			Title:   "My Stream",
			OwnerID: ownerID,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		err = svc.StartStream(ctx, stream.ID, otherID)
		if err == nil {
			t.Fatal("expected error for non-owner start")
		}
		if !errors.Is(err, domain.ErrNotOwner) {
			t.Fatalf("expected ErrNotOwner, got %v", err)
		}
	})

	t.Run("start already live error", func(t *testing.T) {
		svc, _ := newStreamService()
		ctx := context.Background()
		ownerID := uuid.New()

		stream, err := svc.CreateStream(ctx, application.CreateStreamInput{
			Title:   "My Stream",
			OwnerID: ownerID,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		err = svc.StartStream(ctx, stream.ID, ownerID)
		if err != nil {
			t.Fatalf("first start should succeed: %v", err)
		}

		err = svc.StartStream(ctx, stream.ID, ownerID)
		if err == nil {
			t.Fatal("expected error for already live stream")
		}
		if !errors.Is(err, domain.ErrStreamAlreadyLive) {
			t.Fatalf("expected ErrStreamAlreadyLive, got %v", err)
		}
	})
}

func TestStreamService_EndOrphanedLiveStreams(t *testing.T) {
	svc, repo := newStreamService()
	ctx := context.Background()

	live := testutil.NewTestStream(uuid.New())
	live.Status = domain.StreamStatusLive
	live.ListenerCount = 3
	created := testutil.NewTestStream(uuid.New())
	for _, s := range []*domain.Stream{live, created} {
		if err := repo.Create(ctx, s); err != nil {
			t.Fatalf("create: %v", err)
		}
	}

	n, err := svc.EndOrphanedLiveStreams(ctx)
	if err != nil {
		t.Fatalf("EndOrphanedLiveStreams: %v", err)
	}
	if n != 1 {
		t.Fatalf("attendu 1 flux arrete, obtenu %d", n)
	}
	got, _ := repo.FindByID(ctx, live.ID)
	if got.Status != domain.StreamStatusEnded || got.ListenerCount != 0 {
		t.Fatalf("flux live attendu ended sans auditeur, obtenu %s / %d", got.Status, got.ListenerCount)
	}
	untouched, _ := repo.FindByID(ctx, created.ID)
	if untouched.Status != domain.StreamStatusIdle {
		t.Fatalf("flux non live modifie : %s", untouched.Status)
	}
}
