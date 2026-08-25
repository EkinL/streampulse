package testutil

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

func TestMockStreamRepoUpdate(t *testing.T) {
	repo := NewMockStreamRepo()
	ctx := context.Background()

	stream := &domain.Stream{Title: "avant", Description: "d1"}
	if err := repo.Create(ctx, stream); err != nil {
		t.Fatalf("Create: %v", err)
	}

	if err := repo.Update(ctx, &domain.Stream{ID: stream.ID, Title: "apres", Description: "d2"}); err != nil {
		t.Fatalf("Update: %v", err)
	}

	got, err := repo.FindByID(ctx, stream.ID)
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if got.Title != "apres" || got.Description != "d2" {
		t.Fatalf("Update non applique: %+v", got)
	}
	if got.UpdatedAt.IsZero() {
		t.Fatal("UpdatedAt doit etre horodate par Update")
	}
}

func TestMockStreamRepoUpdateUnknownID(t *testing.T) {
	repo := NewMockStreamRepo()

	err := repo.Update(context.Background(), &domain.Stream{ID: uuid.New(), Title: "x"})
	if !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("attendu ErrNotFound, obtenu %v", err)
	}
}
