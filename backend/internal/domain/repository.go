package domain

import (
	"context"

	"github.com/google/uuid"
)

type UserRepository interface {
	Create(ctx context.Context, user *User) error
	FindByEmail(ctx context.Context, email string) (*User, error)
	FindByID(ctx context.Context, id uuid.UUID) (*User, error)
	// FindByProviderSubject retrouve le compte relie a une identite sociale
	// (claim "sub" d'un fournisseur). ErrNotFound si aucune.
	FindByProviderSubject(ctx context.Context, provider, subject string) (*User, error)
	// LinkProviderSubject relie une identite sociale a un compte existant :
	// premiere connexion Google/Apple d'un compte cree par mot de passe.
	LinkProviderSubject(ctx context.Context, id uuid.UUID, provider, subject string) error
	List(ctx context.Context, page, perPage int) ([]User, int, error)
	UpdateRole(ctx context.Context, id uuid.UUID, role Role) error
	// UpdateProfile change l'email et le nom d'utilisateur d'un compte. C'est
	// le droit de rectification du RGPD (art. 16), exerce par la personne
	// elle-meme via PATCH /users/me, voir docs/rgpd.md.
	UpdateProfile(ctx context.Context, id uuid.UUID, email, username string) error
	// Delete efface le compte et, par cascade en base, tout ce qui s'y
	// rattache (jetons, flux, playlists, favoris, morceaux). C'est le droit
	// a l'effacement du RGPD, voir docs/rgpd.md.
	Delete(ctx context.Context, id uuid.UUID) error
}

type StreamRepository interface {
	Create(ctx context.Context, stream *Stream) error
	FindByID(ctx context.Context, id uuid.UUID) (*Stream, error)
	List(ctx context.Context, page, perPage int) ([]Stream, int, error)
	Update(ctx context.Context, stream *Stream) error
	UpdateStatus(ctx context.Context, id uuid.UUID, status StreamStatus) error
	UpdateListenerCount(ctx context.Context, id uuid.UUID, count int) error
	Delete(ctx context.Context, id uuid.UUID) error
	// ListByOwner rend tous les flux d'un diffuseur, sans pagination : sert a
	// fermer ses directs quand son compte est supprime.
	ListByOwner(ctx context.Context, ownerID uuid.UUID) ([]Stream, error)
	// EndLiveStreams passe tous les flux "live" en "ended" et rend leur
	// nombre : nettoyage au demarrage du serveur, quand aucun diffuseur ne
	// peut etre connecte.
	EndLiveStreams(ctx context.Context) (int, error)
}

type PlaylistRepository interface {
	Create(ctx context.Context, playlist *Playlist) error
	FindByID(ctx context.Context, id uuid.UUID) (*Playlist, error)
	ListByOwner(ctx context.Context, ownerID uuid.UUID, page, perPage int) ([]Playlist, int, error)
	ListPublic(ctx context.Context, page, perPage int) ([]Playlist, int, error)
	Update(ctx context.Context, playlist *Playlist) error
	Delete(ctx context.Context, id uuid.UUID) error
	AddTrack(ctx context.Context, playlistID uuid.UUID, track *Track) error
	RemoveTrack(ctx context.Context, playlistID, trackID uuid.UUID) error
	ReorderTracks(ctx context.Context, playlistID uuid.UUID, trackIDs []uuid.UUID) error
}

type RefreshTokenRepository interface {
	Store(ctx context.Context, userID uuid.UUID, tokenHash string, expiresAt interface{}) error
	FindByHash(ctx context.Context, tokenHash string) (uuid.UUID, error)
	DeleteByUserID(ctx context.Context, userID uuid.UUID) error
	DeleteExpired(ctx context.Context) error
}

type FavoriteRepository interface {
	Add(ctx context.Context, userID, streamID uuid.UUID) error
	Remove(ctx context.Context, userID, streamID uuid.UUID) error
	ListByUser(ctx context.Context, userID uuid.UUID, page, perPage int) ([]Stream, int, error)
	Exists(ctx context.Context, userID, streamID uuid.UUID) (bool, error)
}

type MusicFavoriteRepository interface {
	Add(ctx context.Context, userID, musicID uuid.UUID) error
	Remove(ctx context.Context, userID, musicID uuid.UUID) error
	ListByUser(ctx context.Context, userID uuid.UUID, page, perPage int) ([]Music, int, error)
	Exists(ctx context.Context, userID, musicID uuid.UUID) (bool, error)
	ListIDs(ctx context.Context, userID uuid.UUID) ([]uuid.UUID, error)
}

type FeedbackRepository interface {
	Create(ctx context.Context, feedback *Feedback) error
	FindByID(ctx context.Context, id uuid.UUID) (*Feedback, error)
	// List rend tous les signalements, plus recents d'abord, filtres par statut
	// quand status n'est pas vide. Reserve a l'administration : un utilisateur
	// ne consulte pas les signalements des autres.
	List(ctx context.Context, status FeedbackStatus, page, perPage int) ([]Feedback, int, error)
	UpdateStatus(ctx context.Context, id uuid.UUID, status FeedbackStatus) error
}

type MusicRepository interface {
	Create(ctx context.Context, music *Music) error
	FindByID(ctx context.Context, id uuid.UUID) (*Music, error)
	List(ctx context.Context, page, perPage int) ([]Music, int, error)
	Search(ctx context.Context, query string, page, perPage int) ([]Music, int, error)
	ListByUploader(ctx context.Context, uploaderID uuid.UUID, page, perPage int) ([]Music, int, error)
	// AllByUploader rend tous les morceaux d'un compte, sans pagination : sert
	// a retrouver les fichiers a effacer du disque quand le compte est
	// supprime (meme raison d'etre que StreamRepository.ListByOwner).
	AllByUploader(ctx context.Context, uploaderID uuid.UUID) ([]Music, error)
	Update(ctx context.Context, music *Music) error
	Delete(ctx context.Context, id uuid.UUID) error
}
