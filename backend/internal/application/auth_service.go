package application

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"golang.org/x/crypto/bcrypt"
)

type AuthService struct {
	userRepo         domain.UserRepository
	refreshTokenRepo domain.RefreshTokenRepository
	jwt              *auth.JWTManager
	// oauth verifie les ID tokens Google/Apple. Nil quand la connexion
	// sociale n'est pas cablee (tests) : LoginWithOAuth repond alors
	// ErrProviderNotConfigured.
	oauth domain.OAuthVerifier
}

func NewAuthService(userRepo domain.UserRepository, refreshTokenRepo domain.RefreshTokenRepository, jwt *auth.JWTManager, oauth domain.OAuthVerifier) *AuthService {
	return &AuthService{
		userRepo:         userRepo,
		refreshTokenRepo: refreshTokenRepo,
		jwt:              jwt,
		oauth:            oauth,
	}
}

type RegisterInput struct {
	Email    string
	Username string
	Password string
	// AcceptedTerms doit valoir true : voir dto.RegisterRequest.
	AcceptedTerms bool
}

type LoginInput struct {
	Email    string
	Password string
}

type AuthResult struct {
	AccessToken  string
	RefreshToken string
	ExpiresAt    time.Time
	User         *domain.User
}

func (s *AuthService) Register(ctx context.Context, input RegisterInput) (*AuthResult, error) {
	if input.Email == "" || input.Password == "" || input.Username == "" {
		return nil, fmt.Errorf("auth: register: %w", domain.ErrInvalidInput)
	}
	if len(input.Password) < 8 {
		return nil, fmt.Errorf("auth: register: password must be at least 8 characters: %w", domain.ErrInvalidInput)
	}
	if !input.AcceptedTerms {
		return nil, fmt.Errorf("auth: register: terms of use must be accepted: %w", domain.ErrInvalidInput)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(input.Password), 12)
	if err != nil {
		return nil, fmt.Errorf("auth: register: hash password: %w", err)
	}

	user := &domain.User{
		ID:              uuid.New(),
		Email:           input.Email,
		Username:        input.Username,
		PasswordHash:    string(hash),
		Role:            domain.RoleUser,
		TermsAcceptedAt: time.Now().UTC(),
	}

	if err := s.userRepo.Create(ctx, user); err != nil {
		return nil, fmt.Errorf("auth: register: %w", err)
	}

	tokenPair, err := s.jwt.GenerateTokenPair(user)
	if err != nil {
		return nil, fmt.Errorf("auth: register: %w", err)
	}

	tokenHash := auth.HashToken(tokenPair.RefreshToken)
	expiresAt := time.Now().Add(s.jwt.RefreshExpiry())
	if err := s.refreshTokenRepo.Store(ctx, user.ID, tokenHash, expiresAt); err != nil {
		return nil, fmt.Errorf("auth: register: store refresh token: %w", err)
	}

	return &AuthResult{
		AccessToken:  tokenPair.AccessToken,
		RefreshToken: tokenPair.RefreshToken,
		ExpiresAt:    tokenPair.ExpiresAt,
		User:         user,
	}, nil
}

func (s *AuthService) Login(ctx context.Context, input LoginInput) (*AuthResult, error) {
	if input.Email == "" || input.Password == "" {
		return nil, fmt.Errorf("auth: login: %w", domain.ErrInvalidInput)
	}

	user, err := s.userRepo.FindByEmail(ctx, input.Email)
	if err != nil {
		return nil, fmt.Errorf("auth: login: %w", domain.ErrInvalidCredentials)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(input.Password)); err != nil {
		return nil, fmt.Errorf("auth: login: %w", domain.ErrInvalidCredentials)
	}

	// Revoke existing refresh tokens
	_ = s.refreshTokenRepo.DeleteByUserID(ctx, user.ID)

	tokenPair, err := s.jwt.GenerateTokenPair(user)
	if err != nil {
		return nil, fmt.Errorf("auth: login: %w", err)
	}

	tokenHash := auth.HashToken(tokenPair.RefreshToken)
	expiresAt := time.Now().Add(s.jwt.RefreshExpiry())
	if err := s.refreshTokenRepo.Store(ctx, user.ID, tokenHash, expiresAt); err != nil {
		return nil, fmt.Errorf("auth: login: store refresh token: %w", err)
	}

	return &AuthResult{
		AccessToken:  tokenPair.AccessToken,
		RefreshToken: tokenPair.RefreshToken,
		ExpiresAt:    tokenPair.ExpiresAt,
		User:         user,
	}, nil
}

type OAuthLoginInput struct {
	// Provider : domain.ProviderGoogle ou domain.ProviderApple.
	Provider string
	// IDToken est l'ID token (JWT signe par le fournisseur) obtenu par
	// l'application mobile via le SDK Google Sign-In ou Sign in with Apple.
	IDToken string
}

// LoginWithOAuth ouvre une session a partir d'un ID token Google ou Apple.
// Premier passage : le compte est cree (ou relie par email verifie a un
// compte existant). Passages suivants : simple connexion via (provider, sub).
func (s *AuthService) LoginWithOAuth(ctx context.Context, input OAuthLoginInput) (*AuthResult, error) {
	if input.Provider == "" || input.IDToken == "" {
		return nil, fmt.Errorf("auth: oauth login: %w", domain.ErrInvalidInput)
	}
	if s.oauth == nil {
		return nil, fmt.Errorf("auth: oauth login: %w", domain.ErrProviderNotConfigured)
	}

	identity, err := s.oauth.Verify(ctx, input.Provider, input.IDToken)
	if err != nil {
		return nil, fmt.Errorf("auth: oauth login: %w", err)
	}

	user, err := s.userRepo.FindByProviderSubject(ctx, identity.Provider, identity.Subject)
	if errors.Is(err, domain.ErrNotFound) {
		user, err = s.findOrCreateOAuthUser(ctx, identity)
	}
	if err != nil {
		return nil, fmt.Errorf("auth: oauth login: %w", err)
	}

	// Meme ouverture de session que Login : revocation des refresh tokens
	// existants puis emission d'une nouvelle paire.
	_ = s.refreshTokenRepo.DeleteByUserID(ctx, user.ID)

	tokenPair, err := s.jwt.GenerateTokenPair(user)
	if err != nil {
		return nil, fmt.Errorf("auth: oauth login: %w", err)
	}

	tokenHash := auth.HashToken(tokenPair.RefreshToken)
	expiresAt := time.Now().Add(s.jwt.RefreshExpiry())
	if err := s.refreshTokenRepo.Store(ctx, user.ID, tokenHash, expiresAt); err != nil {
		return nil, fmt.Errorf("auth: oauth login: store refresh token: %w", err)
	}

	return &AuthResult{
		AccessToken:  tokenPair.AccessToken,
		RefreshToken: tokenPair.RefreshToken,
		ExpiresAt:    tokenPair.ExpiresAt,
		User:         user,
	}, nil
}

// findOrCreateOAuthUser gere la premiere connexion sociale : reliaison a un
// compte existant quand l'email est verifie par le fournisseur, creation
// d'un compte user sinon.
func (s *AuthService) findOrCreateOAuthUser(ctx context.Context, identity *domain.OAuthIdentity) (*domain.User, error) {
	if identity.Email == "" {
		return nil, fmt.Errorf("email missing from identity token: %w", domain.ErrInvalidInput)
	}

	existing, err := s.userRepo.FindByEmail(ctx, identity.Email)
	if err == nil {
		// On ne relie que si le fournisseur atteste l'adresse : sinon un
		// compte cree chez lui avec l'email d'autrui ouvrirait la session
		// StreamPulse de la victime.
		if !identity.EmailVerified {
			return nil, fmt.Errorf("email not verified by provider: %w", domain.ErrAlreadyExists)
		}
		if err := s.userRepo.LinkProviderSubject(ctx, existing.ID, identity.Provider, identity.Subject); err != nil {
			return nil, err
		}
		existing.AuthProvider = identity.Provider
		existing.ProviderSubject = identity.Subject
		return existing, nil
	}
	if !errors.Is(err, domain.ErrNotFound) {
		return nil, err
	}

	user := &domain.User{
		ID:       uuid.New(),
		Email:    identity.Email,
		Username: usernameFromIdentity(identity),
		// Pas de mot de passe : '' ne matche jamais un hash bcrypt, le
		// login classique reste donc ferme pour ce compte.
		PasswordHash: "",
		Role:         domain.RoleUser,
		// L'ecran de connexion affiche les conditions d'utilisation a cote
		// des boutons sociaux : le premier login social vaut acceptation.
		TermsAcceptedAt: time.Now().UTC(),
		AuthProvider:    identity.Provider,
		ProviderSubject: identity.Subject,
	}
	if err := s.userRepo.Create(ctx, user); err != nil {
		return nil, err
	}
	return user, nil
}

// usernameFromIdentity derive un nom d'affichage : nom donne par le
// fournisseur, sinon partie locale de l'email.
func usernameFromIdentity(identity *domain.OAuthIdentity) string {
	if identity.Name != "" {
		return identity.Name
	}
	if at := strings.IndexByte(identity.Email, '@'); at > 0 {
		return identity.Email[:at]
	}
	return identity.Provider + "-user"
}

func (s *AuthService) RefreshToken(ctx context.Context, refreshToken string) (*AuthResult, error) {
	tokenHash := auth.HashToken(refreshToken)
	userID, err := s.refreshTokenRepo.FindByHash(ctx, tokenHash)
	if err != nil {
		return nil, fmt.Errorf("auth: refresh: %w", err)
	}

	user, err := s.userRepo.FindByID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("auth: refresh: %w", err)
	}

	// Revoke old and issue new
	_ = s.refreshTokenRepo.DeleteByUserID(ctx, user.ID)

	tokenPair, err := s.jwt.GenerateTokenPair(user)
	if err != nil {
		return nil, fmt.Errorf("auth: refresh: %w", err)
	}

	newHash := auth.HashToken(tokenPair.RefreshToken)
	expiresAt := time.Now().Add(s.jwt.RefreshExpiry())
	if err := s.refreshTokenRepo.Store(ctx, user.ID, newHash, expiresAt); err != nil {
		return nil, fmt.Errorf("auth: refresh: store token: %w", err)
	}

	return &AuthResult{
		AccessToken:  tokenPair.AccessToken,
		RefreshToken: tokenPair.RefreshToken,
		ExpiresAt:    tokenPair.ExpiresAt,
		User:         user,
	}, nil
}

func (s *AuthService) ValidateToken(tokenString string) (*auth.Claims, error) {
	return s.jwt.ValidateToken(tokenString)
}
