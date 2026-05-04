package application_test

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/testutil"
)

func newPlaylistService() (*application.PlaylistService, *testutil.MockPlaylistRepo) {
	repo := testutil.NewMockPlaylistRepo()
	svc := application.NewPlaylistService(repo)
	return svc, repo
}

func TestPlaylistService_CreatePlaylist(t *testing.T) {
	t.Run("create playlist", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
			Name:     "Chill Vibes",
			OwnerID:  ownerID,
			IsPublic: true,
		})
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if playlist.Name != "Chill Vibes" {
			t.Fatalf("expected name 'Chill Vibes', got %q", playlist.Name)
		}
		if playlist.OwnerID != ownerID {
			t.Fatalf("expected owner ID %s, got %s", ownerID, playlist.OwnerID)
		}
		if !playlist.IsPublic {
			t.Fatal("expected playlist to be public")
		}
		if playlist.ID == uuid.Nil {
			t.Fatal("expected playlist ID to be assigned")
		}
	})
}

func TestPlaylistService_GetPlaylist(t *testing.T) {
	t.Run("get playlist", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		created, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
			Name:    "Chill Vibes",
			OwnerID: ownerID,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		got, err := svc.GetPlaylist(ctx, created.ID)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if got.Name != "Chill Vibes" {
			t.Fatalf("expected name 'Chill Vibes', got %q", got.Name)
		}
	})
}

func TestPlaylistService_UpdatePlaylist(t *testing.T) {
	t.Run("update playlist not owner error", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()
		otherID := uuid.New()

		created, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
			Name:    "Chill Vibes",
			OwnerID: ownerID,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		_, err = svc.UpdatePlaylist(ctx, application.UpdatePlaylistInput{
			ID:       created.ID,
			Name:     "New Name",
			IsPublic: true,
			OwnerID:  otherID,
		})
		if err == nil {
			t.Fatal("expected error for non-owner update")
		}
		if !errors.Is(err, domain.ErrNotOwner) {
			t.Fatalf("expected ErrNotOwner, got %v", err)
		}
	})
}

func TestPlaylistService_DeletePlaylist(t *testing.T) {
	t.Run("delete playlist", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		created, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
			Name:    "Chill Vibes",
			OwnerID: ownerID,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		err = svc.DeletePlaylist(ctx, created.ID, ownerID)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		_, err = svc.GetPlaylist(ctx, created.ID)
		if err == nil {
			t.Fatal("expected error after deletion")
		}
		if !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("expected ErrNotFound, got %v", err)
		}
	})
}

func TestPlaylistService_AddTrack(t *testing.T) {
	t.Run("add track", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
			Name:    "Chill Vibes",
			OwnerID: ownerID,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		track, err := svc.AddTrack(ctx, application.AddTrackInput{
			PlaylistID: playlist.ID,
			OwnerID:    ownerID,
			Title:      "Song One",
			URL:        "https://example.com/song1.mp3",
			Duration:   240,
		})
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if track.Title != "Song One" {
			t.Fatalf("expected title 'Song One', got %q", track.Title)
		}
		if track.ID == uuid.Nil {
			t.Fatal("expected track ID to be assigned")
		}

		got, err := svc.GetPlaylist(ctx, playlist.ID)
		if err != nil {
			t.Fatalf("get playlist failed: %v", err)
		}
		if len(got.Tracks) != 1 {
			t.Fatalf("expected 1 track, got %d", len(got.Tracks))
		}
	})
}

func TestPlaylistService_RemoveTrack(t *testing.T) {
	t.Run("remove track", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
			Name:    "Chill Vibes",
			OwnerID: ownerID,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		track, err := svc.AddTrack(ctx, application.AddTrackInput{
			PlaylistID: playlist.ID,
			OwnerID:    ownerID,
			Title:      "Song One",
			URL:        "https://example.com/song1.mp3",
			Duration:   240,
		})
		if err != nil {
			t.Fatalf("add track failed: %v", err)
		}

		err = svc.RemoveTrack(ctx, playlist.ID, track.ID, ownerID)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		got, err := svc.GetPlaylist(ctx, playlist.ID)
		if err != nil {
			t.Fatalf("get playlist failed: %v", err)
		}
		if len(got.Tracks) != 0 {
			t.Fatalf("expected 0 tracks after removal, got %d", len(got.Tracks))
		}
	})
}
