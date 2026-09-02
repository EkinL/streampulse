package domain

import (
	"time"

	"github.com/google/uuid"
)

type Role string

const (
	RoleAnonymous   Role = "anonymous"
	RoleUser        Role = "user"
	RoleBroadcaster Role = "broadcaster"
	RoleAdmin       Role = "admin"
)

func (r Role) IsValid() bool {
	switch r {
	case RoleAnonymous, RoleUser, RoleBroadcaster, RoleAdmin:
		return true
	}
	return false
}

func (r Role) AtLeast(min Role) bool {
	return roleLevel(r) >= roleLevel(min)
}

func roleLevel(r Role) int {
	switch r {
	case RoleAnonymous:
		return 0
	case RoleUser:
		return 1
	case RoleBroadcaster:
		return 2
	case RoleAdmin:
		return 3
	default:
		return -1
	}
}

type User struct {
	ID           uuid.UUID
	Email        string
	Username     string
	PasswordHash string
	Role         Role
	// TermsAcceptedAt horodate le consentement donne aux conditions
	// d'utilisation a l'inscription (case a cocher obligatoire, cote client
	// et revalidee cote serveur). Sert de preuve en cas de controle
	// (obligation de rendre compte, docs/rgpd.md).
	TermsAcceptedAt time.Time
	CreatedAt       time.Time
	UpdatedAt       time.Time
}
