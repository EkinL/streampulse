package application_test

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/filestore"
	"github.com/streampulse/backend/testutil"
)

const uploadsBaseURL = "http://files.test/uploads"

func newMusicService(t *testing.T) (*application.MusicService, *testutil.MockMusicRepo, string) {
	t.Helper()
	dir := t.TempDir()
	repo := testutil.NewMockMusicRepo()
	svc := application.NewMusicService(repo, filestore.NewFileStore(dir, uploadsBaseURL))
	return svc, repo, dir
}

func TestMusicService_UploadMusic(t *testing.T) {
	ctx := context.Background()
	uploader := uuid.New()

	t.Run("titre obligatoire, aucun fichier ecrit", func(t *testing.T) {
		svc, _, dir := newMusicService(t)
		_, err := svc.UploadMusic(ctx, "", "Artist", "", 120, "song.mp3", strings.NewReader("audio"), uploader)
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("attendu ErrInvalidInput, obtenu %v", err)
		}
		entries, _ := os.ReadDir(dir)
		if len(entries) != 0 {
			t.Fatalf("un fichier a ete ecrit malgre le refus: %v", entries)
		}
	})

	t.Run("succes : fichier stocke et URL publique", func(t *testing.T) {
		svc, repo, dir := newMusicService(t)
		music, err := svc.UploadMusic(ctx, "Nocturne", "Chopin", "Op. 9", 270, "nocturne.mp3", strings.NewReader("audio-bytes"), uploader)
		if err != nil {
			t.Fatalf("UploadMusic: %v", err)
		}
		if !strings.HasPrefix(music.URL, uploadsBaseURL+"/") || !strings.HasSuffix(music.URL, ".mp3") {
			t.Fatalf("URL inattendue: %s", music.URL)
		}
		entries, _ := os.ReadDir(dir)
		if len(entries) != 1 {
			t.Fatalf("attendu 1 fichier sur disque, obtenu %d", len(entries))
		}
		if _, err := repo.FindByID(ctx, music.ID); err != nil {
			t.Fatalf("le morceau doit etre persiste: %v", err)
		}
		if music.UploadedBy != uploader {
			t.Fatalf("UploadedBy = %s, attendu %s", music.UploadedBy, uploader)
		}
	})
}

func TestMusicService_AddMusicByURL(t *testing.T) {
	ctx := context.Background()
	svc, _, _ := newMusicService(t)

	for _, tc := range []struct{ name, title, url string }{
		{"titre vide", "", "https://cdn.test/a.mp3"},
		{"url vide", "Titre", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := svc.AddMusicByURL(ctx, tc.title, "", "", 0, tc.url, uuid.New())
			if !errors.Is(err, domain.ErrInvalidInput) {
				t.Fatalf("attendu ErrInvalidInput, obtenu %v", err)
			}
		})
	}

	music, err := svc.AddMusicByURL(ctx, "Titre", "Artiste", "Album", 200, "https://cdn.test/a.mp3", uuid.New())
	if err != nil {
		t.Fatalf("AddMusicByURL: %v", err)
	}
	if music.ID == uuid.Nil || music.URL != "https://cdn.test/a.mp3" {
		t.Fatalf("morceau incomplet: %+v", music)
	}
}

func TestMusicService_OwnershipOnUpdateAndDelete(t *testing.T) {
	ctx := context.Background()
	svc, _, _ := newMusicService(t)
	owner, other := uuid.New(), uuid.New()

	music, err := svc.AddMusicByURL(ctx, "Titre", "Artiste", "", 0, "https://cdn.test/a.mp3", owner)
	if err != nil {
		t.Fatalf("AddMusicByURL: %v", err)
	}

	if _, err := svc.UpdateMusic(ctx, music.ID, other, "X", "Y", "Z", ""); !errors.Is(err, domain.ErrNotOwner) {
		t.Fatalf("update par un tiers: attendu ErrNotOwner, obtenu %v", err)
	}
	if err := svc.DeleteMusic(ctx, music.ID, other); !errors.Is(err, domain.ErrNotOwner) {
		t.Fatalf("delete par un tiers: attendu ErrNotOwner, obtenu %v", err)
	}

	updated, err := svc.UpdateMusic(ctx, music.ID, owner, "Nouveau", "Artiste 2", "Album", "https://cdn.test/cover.jpg")
	if err != nil {
		t.Fatalf("UpdateMusic: %v", err)
	}
	if updated.Title != "Nouveau" || updated.CoverURL != "https://cdn.test/cover.jpg" {
		t.Fatalf("mise a jour non appliquee: %+v", updated)
	}

	if err := svc.DeleteMusic(ctx, music.ID, owner); err != nil {
		t.Fatalf("DeleteMusic: %v", err)
	}
	if _, err := svc.GetMusic(ctx, music.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("apres suppression: attendu ErrNotFound, obtenu %v", err)
	}
	// music vient de AddMusicByURL : un lien externe, jamais ecrit sur disque.
	// Sa suppression ne doit rien tenter de retirer.

	if _, err := svc.UpdateMusic(ctx, uuid.New(), owner, "X", "", "", ""); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("update d'un inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := svc.DeleteMusic(ctx, uuid.New(), owner); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("delete d'un inconnu: attendu ErrNotFound, obtenu %v", err)
	}
}

// Sans ca, la ligne en base disparait mais le fichier reste dans uploads/,
// toujours servi par son URL pour qui la connait (limite connue, docs/rgpd.md).
func TestMusicService_DeleteMusicRemovesUploadedFile(t *testing.T) {
	ctx := context.Background()
	svc, _, dir := newMusicService(t)
	owner := uuid.New()

	music, err := svc.UploadMusic(ctx, "Verse", "Studio", "", 42, "prise.mp3", strings.NewReader("audio"), owner)
	if err != nil {
		t.Fatalf("UploadMusic: %v", err)
	}
	if entries, _ := os.ReadDir(dir); len(entries) != 1 {
		t.Fatalf("attendu 1 fichier avant suppression, obtenu %d", len(entries))
	}

	if err := svc.DeleteMusic(ctx, music.ID, owner); err != nil {
		t.Fatalf("DeleteMusic: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("le fichier doit avoir disparu du disque, reste: %v", entries)
	}
}

// Un morceau ajoute par URL externe n'a jamais ete ecrit sur disque : sa
// suppression ne doit rien tenter de retirer (et surtout pas planter).
func TestMusicService_DeleteMusicOnURLTrackTouchesNoFile(t *testing.T) {
	ctx := context.Background()
	svc, _, dir := newMusicService(t)
	owner := uuid.New()

	music, err := svc.AddMusicByURL(ctx, "Externe", "Artiste", "", 0, "https://cdn.test/track.mp3", owner)
	if err != nil {
		t.Fatalf("AddMusicByURL: %v", err)
	}

	if err := svc.DeleteMusic(ctx, music.ID, owner); err != nil {
		t.Fatalf("DeleteMusic: %v", err)
	}
	if entries, _ := os.ReadDir(dir); len(entries) != 0 {
		t.Fatalf("aucun fichier ne devait exister ni disparaitre, obtenu: %v", entries)
	}
}

func TestMusicService_ListAndSearch(t *testing.T) {
	ctx := context.Background()
	svc, _, _ := newMusicService(t)
	uploader := uuid.New()

	for _, tc := range []struct{ title, artist string }{
		{"Nocturne No. 2", "Chopin"},
		{"Clair de lune", "Debussy"},
		{"Gymnopedie", "Satie"},
	} {
		if _, err := svc.AddMusicByURL(ctx, tc.title, tc.artist, "", 0, "https://cdn.test/x.mp3", uploader); err != nil {
			t.Fatalf("AddMusicByURL: %v", err)
		}
	}

	all, total, err := svc.ListMusic(ctx, 0, 0)
	if err != nil {
		t.Fatalf("ListMusic: %v", err)
	}
	if total != 3 || len(all) != 3 {
		t.Fatalf("total=%d len=%d, attendu 3", total, len(all))
	}

	found, total, err := svc.SearchMusic(ctx, "chopin", 1, 20)
	if err != nil {
		t.Fatalf("SearchMusic: %v", err)
	}
	if total != 1 || len(found) != 1 || found[0].Artist != "Chopin" {
		t.Fatalf("recherche 'chopin': total=%d resultats=%+v", total, found)
	}

	_, total, err = svc.SearchMusic(ctx, "inexistant", 1, 20)
	if err != nil {
		t.Fatalf("SearchMusic: %v", err)
	}
	if total != 0 {
		t.Fatalf("recherche sans resultat: total=%d", total)
	}
}
