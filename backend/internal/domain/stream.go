package domain

import (
	"time"

	"github.com/google/uuid"
)

type StreamStatus string

const (
	StreamStatusIdle  StreamStatus = "idle"
	StreamStatusLive  StreamStatus = "live"
	StreamStatusEnded StreamStatus = "ended"
)

func (s StreamStatus) IsValid() bool {
	switch s {
	case StreamStatusIdle, StreamStatusLive, StreamStatusEnded:
		return true
	}
	return false
}

type Stream struct {
	ID            uuid.UUID
	Title         string
	Description   string
	OwnerID       uuid.UUID
	Status        StreamStatus
	ListenerCount int
	Format        string
	CreatedAt     time.Time
	UpdatedAt     time.Time
}
