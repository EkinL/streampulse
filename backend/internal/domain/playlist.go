package domain

import (
	"time"

	"github.com/google/uuid"
)

type Playlist struct {
	ID        uuid.UUID
	Name      string
	OwnerID   uuid.UUID
	IsPublic  bool
	Tracks    []Track
	CreatedAt time.Time
	UpdatedAt time.Time
}

type Track struct {
	ID       uuid.UUID
	Title    string
	URL      string
	Duration int
	Position int
}
