package domain

import (
	"time"

	"github.com/google/uuid"
)

type Playlist struct {
	ID         uuid.UUID
	Name       string
	OwnerID    uuid.UUID
	IsPublic   bool
	Tracks     []Track
	TrackCount int
	CreatedAt  time.Time
	UpdatedAt  time.Time
	// OwnerUsername n'est renseigne que par ListPublic, ou l'on affiche la
	// playlist d'un autre utilisateur et ou le nom du createur a du sens.
	OwnerUsername string
}

type Track struct {
	ID       uuid.UUID
	Title    string
	URL      string
	Duration int
	Position int
}
