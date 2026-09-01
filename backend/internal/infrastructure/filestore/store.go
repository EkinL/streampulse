package filestore

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

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

// DeleteFile efface un fichier uploade a partir de son URL publique telle
// que renvoyee par SaveFile. Une URL qui ne commence pas par baseURL n'a pas
// ete produite par ce FileStore (un lien externe ajoute via AddMusicByURL,
// docs/rgpd.md) : DeleteFile ne fait rien plutot que de risquer d'effacer un
// fichier qui n'est pas le sien.
//
// Le fichier absent (deja efface, ou jamais ecrit) n'est pas une erreur :
// l'appelant nettoie un etat externe qu'il ne controle pas totalement
// (voir MusicService.DeleteMusic et UserService.DeleteUser).
func (fs *FileStore) DeleteFile(url string) error {
	prefix := fs.baseURL + "/"
	if !strings.HasPrefix(url, prefix) {
		return nil
	}

	// filepath.Base retire tout separateur de chemin du nom : meme une URL
	// forgee avec des ".." ne peut pas sortir de baseDir. Le Clean+prefix ci-
	// dessous est une seconde barriere, redondante avec Base seul mais peu
	// couteuse a garder.
	name := filepath.Base(strings.TrimPrefix(url, prefix))
	path := filepath.Join(fs.baseDir, name)
	if !strings.HasPrefix(path, filepath.Clean(fs.baseDir)+string(filepath.Separator)) {
		return fmt.Errorf("filestore: delete file: refusing to remove path outside base dir")
	}

	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("filestore: delete file: %w", err)
	}
	return nil
}
