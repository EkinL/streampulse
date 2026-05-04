package application

import (
	"context"
	"fmt"
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
}

func NewAuthService(userRepo domain.UserRepository, refreshTokenRepo domain.RefreshTokenRepository, jwt *auth.JWTManager) *AuthService {
	return &AuthService{
		userRepo:         userRepo,
		refreshTokenRepo: refreshTokenRepo,
		jwt:              jwt,
	}
}

type RegisterInput struct {
	Email    string
	Username string
	Password string
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

	hash, err := bcrypt.GenerateFromPassword([]byte(input.Password), 12)
	if err != nil {
		return nil, fmt.Errorf("auth: register: hash password: %w", err)
	}

	user := &domain.User{
		ID:           uuid.New(),
		Email:        input.Email,
		Username:     input.Username,
		PasswordHash: string(hash),
		Role:         domain.RoleUser,
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
