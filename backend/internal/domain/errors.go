package domain

import "errors"

var (
	ErrNotFound           = errors.New("resource not found")
	ErrAlreadyExists      = errors.New("resource already exists")
	ErrInvalidInput       = errors.New("invalid input")
	ErrUnauthorized       = errors.New("unauthorized")
	ErrForbidden          = errors.New("forbidden")
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrTokenExpired       = errors.New("token expired")
	ErrTokenInvalid       = errors.New("token invalid")
	// ErrProviderNotConfigured : connexion sociale demandee alors que le
	// fournisseur (Google ou Apple) n'a pas d'audience configuree via les
	// variables d'env GOOGLE_OAUTH_CLIENT_IDS / APPLE_OAUTH_CLIENT_IDS.
	ErrProviderNotConfigured = errors.New("oauth provider not configured")
	ErrStreamNotLive         = errors.New("stream is not live")
	ErrStreamAlreadyLive     = errors.New("stream is already live")
	ErrNotOwner              = errors.New("not the owner of this resource")
)
