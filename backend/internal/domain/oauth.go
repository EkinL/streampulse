package domain

import "context"

// OAuthIdentity est ce que prouve un ID token verifie : une personne
// identifiee par (Provider, Subject) chez un fournisseur d'identite.
type OAuthIdentity struct {
	Provider string
	// Subject est la claim "sub" du token : stable pour la vie du compte
	// chez le fournisseur.
	Subject string
	Email   string
	// EmailVerified reprend la claim du fournisseur. On ne relie un compte
	// existant par email que si elle vaut true : sinon n'importe qui
	// pourrait revendiquer l'adresse d'autrui aupres du fournisseur et
	// prendre la main sur le compte StreamPulse correspondant.
	EmailVerified bool
	// Name est le nom d'affichage quand le fournisseur le donne (Google).
	Name string
}

// OAuthVerifier verifie un ID token emis par un fournisseur d'identite
// (signature via son JWKS, emetteur, audience, expiration) et en extrait
// l'identite. Implemente par infrastructure/auth.OIDCVerifier.
type OAuthVerifier interface {
	Verify(ctx context.Context, provider, idToken string) (*OAuthIdentity, error)
}
