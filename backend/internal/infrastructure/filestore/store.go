package filestore

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/google/uuid"
)

type FileStore struct {
	baseDir string
	baseURL string
}

func NewFileStore(baseDir, baseURL string) *FileStore {
	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		panic(fmt.Sprintf("filestore: failed to create directory %s: %v", baseDir, err))
	}
	return &FileStore{
		baseDir: baseDir,
		baseURL: baseURL,
	}
}

func (fs *FileStore) SaveFile(filename string, data io.Reader) (string, error) {
	ext := filepath.Ext(filename)
	newName := uuid.New().String() + ext

	path := filepath.Join(fs.baseDir, newName)
	dst, err := os.Create(path)
	if err != nil {
		return "", fmt.Errorf("filestore: create file: %w", err)
	}

	// Sur chaque sortie en erreur on retire le fichier : sinon il reste sur
	// disque, tronque et reference par personne, puisque le nom vient d'un
	// UUID genere ici et n'est rendu a l'appelant qu'en cas de succes.
	if _, err := io.Copy(dst, data); err != nil {
		_ = dst.Close()
		_ = os.Remove(path)
		return "", fmt.Errorf("filestore: write file: %w", err)
	}

	// Close explicite et verifie : c'est lui qui remonte une ecriture
	// incomplete (disque plein, quota), qu'un defer aurait avalee.
	if err := dst.Close(); err != nil {
		_ = os.Remove(path)
		return "", fmt.Errorf("filestore: close file: %w", err)
	}

	return fs.baseURL + "/" + newName, nil
}
