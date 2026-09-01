package application

import (
	"context"
	"fmt"
	"io"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/filestore"
)

type MusicService struct {
	musicRepo domain.MusicRepository
	fileStore *filestore.FileStore
}

func NewMusicService(musicRepo domain.MusicRepository, fileStore *filestore.FileStore) *MusicService {
	return &MusicService{
		musicRepo: musicRepo,
		fileStore: fileStore,
	}
}

func (s *MusicService) UploadMusic(ctx context.Context, title, artist, album string, duration int, filename string, fileData io.Reader, uploaderID uuid.UUID) (*domain.Music, error) {
	if title == "" {
		return nil, fmt.Errorf("music: upload: title is required: %w", domain.ErrInvalidInput)
	}

	url, err := s.fileStore.SaveFile(filename, fileData)
	if err != nil {
		return nil, fmt.Errorf("music: upload: %w", err)
	}

	music := &domain.Music{
		Title:      title,
		Artist:     artist,
		Album:      album,
		Duration:   duration,
		URL:        url,
		UploadedBy: uploaderID,
	}

	if err := s.musicRepo.Create(ctx, music); err != nil {
		return nil, fmt.Errorf("music: upload: %w", err)
	}
	return music, nil
}

func (s *MusicService) AddMusicByURL(ctx context.Context, title, artist, album string, duration int, url string, uploaderID uuid.UUID) (*domain.Music, error) {
	if title == "" {
		return nil, fmt.Errorf("music: add_by_url: title is required: %w", domain.ErrInvalidInput)
	}
	if url == "" {
		return nil, fmt.Errorf("music: add_by_url: url is required: %w", domain.ErrInvalidInput)
	}

	music := &domain.Music{
		Title:      title,
		Artist:     artist,
		Album:      album,
		Duration:   duration,
		URL:        url,
		UploadedBy: uploaderID,
	}

	if err := s.musicRepo.Create(ctx, music); err != nil {
		return nil, fmt.Errorf("music: add_by_url: %w", err)
	}
	return music, nil
}

func (s *MusicService) GetMusic(ctx context.Context, id uuid.UUID) (*domain.Music, error) {
	music, err := s.musicRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("music: get: %w", err)
	}
	return music, nil
}

func (s *MusicService) ListMusic(ctx context.Context, page, perPage int) ([]domain.Music, int, error) {
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 {
		perPage = 20
	}
	tracks, total, err := s.musicRepo.List(ctx, page, perPage)
	if err != nil {
		return nil, 0, fmt.Errorf("music: list: %w", err)
	}
	return tracks, total, nil
}

func (s *MusicService) SearchMusic(ctx context.Context, query string, page, perPage int) ([]domain.Music, int, error) {
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 {
		perPage = 20
	}
	tracks, total, err := s.musicRepo.Search(ctx, query, page, perPage)
	if err != nil {
		return nil, 0, fmt.Errorf("music: search: %w", err)
	}
	return tracks, total, nil
}

func (s *MusicService) UpdateMusic(ctx context.Context, id, ownerID uuid.UUID, title, artist, album string, coverURL string) (*domain.Music, error) {
	music, err := s.musicRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("music: update: %w", err)
	}
	if music.UploadedBy != ownerID {
		return nil, fmt.Errorf("music: update: %w", domain.ErrNotOwner)
	}

	music.Title = title
	music.Artist = artist
	music.Album = album
	music.CoverURL = coverURL

	if err := s.musicRepo.Update(ctx, music); err != nil {
		return nil, fmt.Errorf("music: update: %w", err)
	}
	return music, nil
}

// DeleteMusic efface le morceau et, s'il s'agit d'un fichier verse (pas d'un
// lien externe ajoute par AddMusicByURL), le fichier sous-jacent dans
// uploads/ : sinon il reste sur disque, toujours servi par son URL pour qui
// la connait (limite connue, docs/rgpd.md). fileStore.DeleteFile ignore
// silencieusement les URLs qu'il n'a pas produites, donc l'appel est fait
// dans tous les cas.
//
// L'echec de l'effacement du fichier n'annule pas la suppression : la ligne
// en base est deja partie, et il n'y a rien d'utile a renvoyer au client
// pour un probleme cote disque qu'il ne peut pas resoudre.
func (s *MusicService) DeleteMusic(ctx context.Context, id, ownerID uuid.UUID) error {
	music, err := s.musicRepo.FindByID(ctx, id)
	if err != nil {
		return fmt.Errorf("music: delete: %w", err)
	}
	if music.UploadedBy != ownerID {
		return fmt.Errorf("music: delete: %w", domain.ErrNotOwner)
	}
	if err := s.musicRepo.Delete(ctx, id); err != nil {
		return fmt.Errorf("music: delete: %w", err)
	}
	_ = s.fileStore.DeleteFile(music.URL)
	return nil
}
