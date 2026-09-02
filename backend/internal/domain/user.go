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

// Fournisseurs d'identite acceptes pour la connexion sociale. "local"
// designe un compte cree par email + mot de passe.
const (
	ProviderLocal  = "local"
	ProviderGoogle = "google"
	ProviderApple  = "apple"
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
	// AuthProvider dit d'ou vient l'identite du compte : ProviderLocal pour
	// un compte email + mot de passe, ProviderGoogle/ProviderApple pour un
	// compte cree ou relie via la connexion sociale.
	AuthProvider string
	// ProviderSubject est l'identifiant stable ("sub") delivre par le
	// fournisseur d'identite. Vide pour un compte local. C'est lui, et non
	// l'email (changeant, ou relais prive chez Apple), qui identifie le
	// compte social.
	ProviderSubject string
	CreatedAt       time.Time
	UpdatedAt       time.Time
}
