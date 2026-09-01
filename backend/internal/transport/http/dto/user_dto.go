package dto

import "time"

// ProfileDTO est la reponse de GET /users/me : l'integralite des donnees
// personnelles conservees sur un compte (droit d'acces, docs/rgpd.md). Le
// hash du mot de passe n'en fait volontairement pas partie.
type ProfileDTO struct {
	ID              string    `json:"id"`
	Email           string    `json:"email"`
	Username        string    `json:"username"`
	Role            string    `json:"role"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
	TermsAcceptedAt time.Time `json:"terms_accepted_at"`
}
