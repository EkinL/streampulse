package application_test

import (
	"context"
	"errors"
	"fmt"
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

		got, err := svc.GetPlaylist(ctx, created.ID, ownerID)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if got.Name != "Chill Vibes" {
			t.Fatalf("expected name 'Chill Vibes', got %q", got.Name)
		}
	})

	t.Run("private playlist hidden from non-owner", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()
		otherID := uuid.New()

		created, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
			Name:     "Secret Mix",
			OwnerID:  ownerID,
			IsPublic: false,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		_, err = svc.GetPlaylist(ctx, created.ID, otherID)
		if !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("expected ErrNotFound for non-owner on private playlist, got %v", err)
		}
	})

	t.Run("public playlist visible to anyone", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()
		otherID := uuid.New()

		created, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
			Name:     "Open Mix",
			OwnerID:  ownerID,
			IsPublic: true,
		})
		if err != nil {
			t.Fatalf("create failed: %v", err)
		}

		got, err := svc.GetPlaylist(ctx, created.ID, otherID)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if got.ID != created.ID {
			t.Fatalf("expected playlist %s, got %s", created.ID, got.ID)
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

		_, err = svc.GetPlaylist(ctx, created.ID, ownerID)
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

		got, err := svc.GetPlaylist(ctx, playlist.ID, ownerID)
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

		got, err := svc.GetPlaylist(ctx, playlist.ID, ownerID)
		if err != nil {
			t.Fatalf("get playlist failed: %v", err)
		}
		if len(got.Tracks) != 0 {
			t.Fatalf("expected 0 tracks after removal, got %d", len(got.Tracks))
		}
	})

	t.Run("positions are compacted after removal", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, tracks := seedPlaylistWithTracks(t, svc, ownerID, 3)

		// Remove the middle track: the last one must slide from 2 to 1.
		if err := svc.RemoveTrack(ctx, playlist.ID, tracks[1].ID, ownerID); err != nil {
			t.Fatalf("remove track failed: %v", err)
		}

		got, err := svc.GetPlaylist(ctx, playlist.ID, ownerID)
		if err != nil {
			t.Fatalf("get playlist failed: %v", err)
		}
		if len(got.Tracks) != 2 {
			t.Fatalf("expected 2 tracks, got %d", len(got.Tracks))
		}
		for i, tr := range got.Tracks {
			if tr.Position != i {
				t.Fatalf("expected track %d at position %d, got %d", i, i, tr.Position)
			}
		}
		if got.Tracks[0].ID != tracks[0].ID || got.Tracks[1].ID != tracks[2].ID {
			t.Fatal("expected remaining tracks to keep their relative order")
		}
	})
}

// seedPlaylistWithTracks creates a playlist owned by ownerID with n tracks.
func seedPlaylistWithTracks(t *testing.T, svc *application.PlaylistService, ownerID uuid.UUID, n int) (*domain.Playlist, []*domain.Track) {
	t.Helper()
	ctx := context.Background()

	playlist, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{
		Name:    "Chill Vibes",
		OwnerID: ownerID,
	})
	if err != nil {
		t.Fatalf("create playlist failed: %v", err)
	}

	tracks := make([]*domain.Track, 0, n)
	for i := 0; i < n; i++ {
		track, err := svc.AddTrack(ctx, application.AddTrackInput{
			PlaylistID: playlist.ID,
			OwnerID:    ownerID,
			Title:      fmt.Sprintf("Song %d", i+1),
			URL:        fmt.Sprintf("https://example.com/song%d.mp3", i+1),
			Duration:   200 + i,
		})
		if err != nil {
			t.Fatalf("add track %d failed: %v", i, err)
		}
		tracks = append(tracks, track)
	}
	return playlist, tracks
}

func TestPlaylistService_ReorderTracks(t *testing.T) {
	t.Run("reorder tracks", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, tracks := seedPlaylistWithTracks(t, svc, ownerID, 3)

		// Reverse the play order.
		updated, err := svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: playlist.ID,
			OwnerID:    ownerID,
			TrackIDs:   []uuid.UUID{tracks[2].ID, tracks[1].ID, tracks[0].ID},
		})
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if len(updated.Tracks) != 3 {
			t.Fatalf("expected 3 tracks, got %d", len(updated.Tracks))
		}
		for i, want := range []uuid.UUID{tracks[2].ID, tracks[1].ID, tracks[0].ID} {
			if updated.Tracks[i].ID != want {
				t.Fatalf("position %d: expected track %s, got %s", i, want, updated.Tracks[i].ID)
			}
			if updated.Tracks[i].Position != i {
				t.Fatalf("position %d: expected position %d, got %d", i, i, updated.Tracks[i].Position)
			}
		}
	})

	t.Run("reorder not owner error", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, tracks := seedPlaylistWithTracks(t, svc, ownerID, 2)

		_, err := svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: playlist.ID,
			OwnerID:    uuid.New(),
			TrackIDs:   []uuid.UUID{tracks[1].ID, tracks[0].ID},
		})
		if !errors.Is(err, domain.ErrNotOwner) {
			t.Fatalf("expected ErrNotOwner, got %v", err)
		}
	})

	t.Run("reorder empty list error", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, _ := seedPlaylistWithTracks(t, svc, ownerID, 2)

		_, err := svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: playlist.ID,
			OwnerID:    ownerID,
			TrackIDs:   nil,
		})
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}
	})

	t.Run("reorder duplicate ids error", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, tracks := seedPlaylistWithTracks(t, svc, ownerID, 2)

		// [A, A] has the right length but would silently drop track B.
		_, err := svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: playlist.ID,
			OwnerID:    ownerID,
			TrackIDs:   []uuid.UUID{tracks[0].ID, tracks[0].ID},
		})
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}
	})

	t.Run("reorder incomplete list error", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, tracks := seedPlaylistWithTracks(t, svc, ownerID, 3)

		_, err := svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: playlist.ID,
			OwnerID:    ownerID,
			TrackIDs:   []uuid.UUID{tracks[0].ID, tracks[1].ID},
		})
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}
	})

	t.Run("reorder unknown track error", func(t *testing.T) {
		svc, _ := newPlaylistService()
		ctx := context.Background()
		ownerID := uuid.New()

		playlist, tracks := seedPlaylistWithTracks(t, svc, ownerID, 2)

		_, err := svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: playlist.ID,
			OwnerID:    ownerID,
			TrackIDs:   []uuid.UUID{tracks[0].ID, uuid.New()},
		})
		if !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("expected ErrNotFound, got %v", err)
		}
	})
}
