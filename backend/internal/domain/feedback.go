package domain

import (
	"time"

	"github.com/google/uuid"
)

type FeedbackType string

const (
	FeedbackTypeBug        FeedbackType = "bug"
	FeedbackTypeSuggestion FeedbackType = "suggestion"
	FeedbackTypeOther      FeedbackType = "other"
)

func (t FeedbackType) IsValid() bool {
	switch t {
	case FeedbackTypeBug, FeedbackTypeSuggestion, FeedbackTypeOther:
		return true
	}
	return false
}

type FeedbackStatus string

const (
	FeedbackStatusNew        FeedbackStatus = "new"
	FeedbackStatusInProgress FeedbackStatus = "in_progress"
	FeedbackStatusResolved   FeedbackStatus = "resolved"
)

func (s FeedbackStatus) IsValid() bool {
	switch s {
	case FeedbackStatusNew, FeedbackStatusInProgress, FeedbackStatusResolved:
		return true
	}
	return false
}

// Feedback est signale par un compte authentifie, quel que soit son role :
// c'est le canal par lequel un probleme ou une suggestion remonte a
// l'equipe, en dehors de l'espace public des issues GitHub.
type Feedback struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	Type       FeedbackType
	Message    string
	AppVersion string
	Platform   string
	Status     FeedbackStatus
	CreatedAt  time.Time
	UpdatedAt  time.Time
}
