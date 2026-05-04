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

	dst, err := os.Create(filepath.Join(fs.baseDir, newName))
	if err != nil {
		return "", fmt.Errorf("filestore: create file: %w", err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, data); err != nil {
		return "", fmt.Errorf("filestore: write file: %w", err)
	}

	return fs.baseURL + "/" + newName, nil
}
