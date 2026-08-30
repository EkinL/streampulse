// Les mocks sont le socle de toute la suite unitaire : ce fichier verifie
// leurs contrats aux bords (pagination au-dela du total, identifiants
// inconnus), la ou un ecart avec le vrai repository fausserait les tests qui
// s'appuient dessus.
package testutil

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

func TestMockUserRepoListBeyondTotal(t *testing.T) {
	repo := NewMockUserRepo()
	ctx := context.Background()
	if err := repo.Create(ctx, NewTestUser(domain.RoleUser)); err != nil {
		t.Fatalf("Create: %v", err)
	}

	users, total, err := repo.List(ctx, 99, 20)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if total != 1 || len(users) != 0 {
		t.Fatalf("attendu 0 resultat (total 1), obtenu %d (total %d)", len(users), total)
	}
}

func TestMockStreamRepoEdges(t *testing.T) {
	repo := NewMockStreamRepo()
	ctx := context.Background()
	unknown := uuid.New()

	if _, err := repo.FindByID(ctx, unknown); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("FindByID inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.UpdateStatus(ctx, unknown, domain.StreamStatusLive); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("UpdateStatus inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.UpdateListenerCount(ctx, unknown, 3); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("UpdateListenerCount inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.Delete(ctx, unknown); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Delete inconnu: attendu ErrNotFound, obtenu %v", err)
	}

	stream := NewTestStream(uuid.New())
	if err := repo.Create(ctx, stream); err != nil {
		t.Fatalf("Create: %v", err)
	}

	if err := repo.UpdateListenerCount(ctx, stream.ID, 7); err != nil {
		t.Fatalf("UpdateListenerCount: %v", err)
	}
	got, err := repo.FindByID(ctx, stream.ID)
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if got.ListenerCount != 7 {
		t.Fatalf("compteur attendu 7, obtenu %d", got.ListenerCount)
	}

	streams, total, err := repo.List(ctx, 99, 20)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if total != 1 || len(streams) != 0 {
		t.Fatalf("attendu 0 resultat (total 1), obtenu %d (total %d)", len(streams), total)
	}

	if err := repo.Delete(ctx, stream.ID); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := repo.FindByID(ctx, stream.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("le flux doit avoir disparu, obtenu %v", err)
	}
}

func TestMockRefreshTokenRepoEdges(t *testing.T) {
	repo := NewMockRefreshTokenRepo()
	ctx := context.Background()

	if _, err := repo.FindByHash(ctx, "inconnu"); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("FindByHash inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	// Le mock n'a pas de notion d'expiration : l'appel doit juste reussir.
	if err := repo.DeleteExpired(ctx); err != nil {
		t.Fatalf("DeleteExpired: %v", err)
	}
}

func TestMockPlaylistRepoEdges(t *testing.T) {
	repo := NewMockPlaylistRepo()
	ctx := context.Background()
	unknown := uuid.New()

	if err := repo.Update(ctx, NewTestPlaylist(uuid.New())); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Update inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.Delete(ctx, unknown); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Delete inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.AddTrack(ctx, unknown, NewTestTrack()); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("AddTrack inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.RemoveTrack(ctx, unknown, uuid.New()); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("RemoveTrack playlist inconnue: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.ReorderTracks(ctx, unknown, []uuid.UUID{uuid.New()}); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("ReorderTracks inconnu: attendu ErrNotFound, obtenu %v", err)
	}

	ownerID := uuid.New()
	playlist := NewTestPlaylist(ownerID)
	if err := repo.Create(ctx, playlist); err != nil {
		t.Fatalf("Create: %v", err)
	}
	if err := repo.RemoveTrack(ctx, playlist.ID, uuid.New()); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("RemoveTrack piste inconnue: attendu ErrNotFound, obtenu %v", err)
	}

	playlists, total, err := repo.ListByOwner(ctx, ownerID, 99, 20)
	if err != nil {
		t.Fatalf("ListByOwner: %v", err)
	}
	if total != 1 || len(playlists) != 0 {
		t.Fatalf("attendu 0 resultat (total 1), obtenu %d (total %d)", len(playlists), total)
	}
}

func TestMockMusicRepoEdges(t *testing.T) {
	repo := NewMockMusicRepo()
	ctx := context.Background()
	uploaderID := uuid.New()

	if err := repo.Update(ctx, &domain.Music{ID: uuid.New()}); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Update inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.Delete(ctx, uuid.New()); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Delete inconnu: attendu ErrNotFound, obtenu %v", err)
	}

	music := &domain.Music{Title: "t", Artist: "a", UploadedBy: uploaderID}
	if err := repo.Create(ctx, music); err != nil {
		t.Fatalf("Create: %v", err)
	}
	if err := repo.Create(ctx, &domain.Music{Title: "autre", UploadedBy: uuid.New()}); err != nil {
		t.Fatalf("Create: %v", err)
	}

	mine, total, err := repo.ListByUploader(ctx, uploaderID, 1, 20)
	if err != nil {
		t.Fatalf("ListByUploader: %v", err)
	}
	if total != 1 || len(mine) != 1 || mine[0].ID != music.ID {
		t.Fatalf("attendu le seul morceau de l'uploader, obtenu %+v (total %d)", mine, total)
	}
}
