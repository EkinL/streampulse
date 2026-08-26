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
