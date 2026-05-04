package domain

import (
	"time"

	"github.com/google/uuid"
)

type Music struct {
	ID         uuid.UUID
	Title      string
	Artist     string
	Album      string
	Duration   int
	URL        string
	CoverURL   string
	UploadedBy uuid.UUID
	CreatedAt  time.Time
}
