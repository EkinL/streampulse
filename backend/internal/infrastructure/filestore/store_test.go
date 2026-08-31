package filestore_test

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/streampulse/backend/internal/infrastructure/filestore"
)

// failingReader livre quelques octets puis echoue, comme une connexion
// coupee en plein upload.
type failingReader struct {
	data []byte
	sent bool
}

func (r *failingReader) Read(p []byte) (int, error) {
	if !r.sent {
		r.sent = true
		return copy(p, r.data), nil
	}
	return 0, errors.New("network dropped")
}

func TestSaveFileWritesContentAndReturnsURL(t *testing.T) {
	dir := t.TempDir()
	fs := filestore.NewFileStore(dir, "http://api.test/uploads")

	url, err := fs.SaveFile("track.mp3", strings.NewReader("audio-bytes"))
	if err != nil {
		t.Fatalf("SaveFile: %v", err)
	}
	if !strings.HasPrefix(url, "http://api.test/uploads/") {
		t.Fatalf("URL inattendue: %q", url)
	}
	if !strings.HasSuffix(url, ".mp3") {
		t.Fatalf("extension perdue: %q", url)
	}

	name := strings.TrimPrefix(url, "http://api.test/uploads/")
	content, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		t.Fatalf("fichier absent du disque: %v", err)
	}
	if string(content) != "audio-bytes" {
		t.Fatalf("contenu = %q, attendu %q", content, "audio-bytes")
	}
}

func TestSaveFileGeneratesUniqueNames(t *testing.T) {
	fs := filestore.NewFileStore(t.TempDir(), "http://api.test/uploads")

	a, err := fs.SaveFile("same.mp3", strings.NewReader("a"))
	if err != nil {
		t.Fatalf("SaveFile a: %v", err)
	}
	b, err := fs.SaveFile("same.mp3", strings.NewReader("b"))
	if err != nil {
		t.Fatalf("SaveFile b: %v", err)
	}
	if a == b {
		t.Fatalf("deux uploads du meme nom doivent donner deux URLs distinctes, obtenu %q", a)
	}
}

// Contrat repare par le fix errcheck : un upload qui echoue ne renvoie pas
// d'URL et ne laisse aucun fichier tronque sur le disque.
func TestSaveFileFailedUploadLeavesNoOrphan(t *testing.T) {
	dir := t.TempDir()
	fs := filestore.NewFileStore(dir, "http://api.test/uploads")

	if _, err := fs.SaveFile("track.mp3", &failingReader{data: []byte("partial")}); err == nil {
		t.Fatal("SaveFile aurait du echouer")
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("fichier orphelin laisse sur disque: %v", entries[0].Name())
	}
}

func TestDeleteFileRemovesAnUploadedFile(t *testing.T) {
	dir := t.TempDir()
	fs := filestore.NewFileStore(dir, "http://api.test/uploads")

	url, err := fs.SaveFile("track.mp3", strings.NewReader("audio-bytes"))
	if err != nil {
		t.Fatalf("SaveFile: %v", err)
	}

	if err := fs.DeleteFile(url); err != nil {
		t.Fatalf("DeleteFile: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("le fichier doit avoir disparu, obtenu: %v", entries)
	}
}

// Un lien ajoute via AddMusicByURL ne vient pas de ce FileStore : DeleteFile
// doit l'ignorer plutot que de risquer d'effacer un fichier qui n'est pas le
// sien (docs/rgpd.md).
func TestDeleteFileIgnoresExternalURLs(t *testing.T) {
	dir := t.TempDir()
	fs := filestore.NewFileStore(dir, "http://api.test/uploads")

	if err := fs.DeleteFile("https://cdn.test/track.mp3"); err != nil {
		t.Fatalf("DeleteFile sur une URL externe ne doit pas echouer: %v", err)
	}
}

// Effacer deux fois, ou un fichier deja disparu, n'est pas une erreur :
// l'appelant (MusicService.DeleteMusic, UserService.DeleteUser) nettoie un
// etat externe qu'il ne controle pas totalement.
func TestDeleteFileIsIdempotent(t *testing.T) {
	fs := filestore.NewFileStore(t.TempDir(), "http://api.test/uploads")

	if err := fs.DeleteFile("http://api.test/uploads/jamais-ecrit.mp3"); err != nil {
		t.Fatalf("DeleteFile sur un fichier absent ne doit pas echouer: %v", err)
	}
}

// Une URL forgee avec des segments ".." ne doit jamais faire sortir la
// suppression de baseDir.
func TestDeleteFileRejectsPathTraversal(t *testing.T) {
	dir := t.TempDir()
	fs := filestore.NewFileStore(dir, "http://api.test/uploads")

	outside := filepath.Join(filepath.Dir(dir), "canary.txt")
	if err := os.WriteFile(outside, []byte("ne doit pas disparaitre"), 0o644); err != nil {
		t.Fatalf("preparation du fichier temoin: %v", err)
	}
	defer func() { _ = os.Remove(outside) }()

	_ = fs.DeleteFile("http://api.test/uploads/../canary.txt")

	if _, err := os.Stat(outside); err != nil {
		t.Fatalf("le fichier hors baseDir a disparu: %v", err)
	}
}
