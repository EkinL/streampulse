package application_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/testutil"
)

func newAuthService() (*application.AuthService, *testutil.MockUserRepo, *testutil.MockRefreshTokenRepo) {
	userRepo := testutil.NewMockUserRepo()
	refreshTokenRepo := testutil.NewMockRefreshTokenRepo()
	jwtManager := auth.NewJWTManager("test-secret-key-for-unit-tests", 15*time.Minute, 168*time.Hour)
	svc := application.NewAuthService(userRepo, refreshTokenRepo, jwtManager, nil)
	return svc, userRepo, refreshTokenRepo
}

func TestAuthService_Register(t *testing.T) {
	t.Run("successful register", func(t *testing.T) {
		svc, _, _ := newAuthService()
		ctx := context.Background()

		result, err := svc.Register(ctx, application.RegisterInput{
			Email:         "alice@example.com",
			Username:      "alice",
			Password:      "securepassword123",
			AcceptedTerms: true,
		})
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if result.AccessToken == "" {
			t.Fatal("expected access token to be non-empty")
		}
		if result.RefreshToken == "" {
			t.Fatal("expected refresh token to be non-empty")
		}
		if result.User == nil {
			t.Fatal("expected user to be non-nil")
		}
		if result.User.Email != "alice@example.com" {
			t.Fatalf("expected email alice@example.com, got %s", result.User.Email)
		}
		if result.User.TermsAcceptedAt.IsZero() {
			t.Fatal("expected terms acceptance to be timestamped")
		}
		if result.User.Role != domain.RoleUser {
			t.Fatalf("expected role %s, got %s", domain.RoleUser, result.User.Role)
		}
	})

	t.Run("register with existing email", func(t *testing.T) {
		svc, _, _ := newAuthService()
		ctx := context.Background()

		_, err := svc.Register(ctx, application.RegisterInput{
			Email:         "alice@example.com",
			Username:      "alice",
			Password:      "securepassword123",
			AcceptedTerms: true,
		})
		if err != nil {
			t.Fatalf("first register should succeed, got %v", err)
		}

		_, err = svc.Register(ctx, application.RegisterInput{
			Email:         "alice@example.com",
			Username:      "alice2",
			Password:      "anotherpassword123",
			AcceptedTerms: true,
		})
		if err == nil {
			t.Fatal("expected error for duplicate email")
		}
		if !errors.Is(err, domain.ErrAlreadyExists) {
			t.Fatalf("expected ErrAlreadyExists, got %v", err)
		}
	})

	t.Run("register with short password", func(t *testing.T) {
		svc, _, _ := newAuthService()
		ctx := context.Background()

		_, err := svc.Register(ctx, application.RegisterInput{
			Email:         "bob@example.com",
			Username:      "bob",
			Password:      "short",
			AcceptedTerms: true,
		})
		if err == nil {
			t.Fatal("expected error for short password")
		}
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}
	})

	t.Run("register without accepting terms", func(t *testing.T) {
		svc, _, _ := newAuthService()
		ctx := context.Background()

		_, err := svc.Register(ctx, application.RegisterInput{
			Email:    "carol@example.com",
			Username: "carol",
			Password: "securepassword123",
		})
		if err == nil {
			t.Fatal("expected error when terms are not accepted")
		}
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}
	})
}

func TestAuthService_Login(t *testing.T) {
	t.Run("successful login", func(t *testing.T) {
		svc, _, _ := newAuthService()
		ctx := context.Background()

		_, err := svc.Register(ctx, application.RegisterInput{
			Email:         "alice@example.com",
			Username:      "alice",
			Password:      "securepassword123",
			AcceptedTerms: true,
		})
		if err != nil {
			t.Fatalf("register failed: %v", err)
		}

		result, err := svc.Login(ctx, application.LoginInput{
			Email:    "alice@example.com",
			Password: "securepassword123",
		})
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if result.AccessToken == "" {
			t.Fatal("expected access token to be non-empty")
		}
		if result.RefreshToken == "" {
			t.Fatal("expected refresh token to be non-empty")
		}
		if result.User.Email != "alice@example.com" {
			t.Fatalf("expected email alice@example.com, got %s", result.User.Email)
		}
	})

	t.Run("login with wrong password", func(t *testing.T) {
		svc, _, _ := newAuthService()
		ctx := context.Background()

		_, err := svc.Register(ctx, application.RegisterInput{
			Email:         "alice@example.com",
			Username:      "alice",
			Password:      "securepassword123",
			AcceptedTerms: true,
		})
		if err != nil {
			t.Fatalf("register failed: %v", err)
		}

		_, err = svc.Login(ctx, application.LoginInput{
			Email:    "alice@example.com",
			Password: "wrongpassword",
		})
		if err == nil {
			t.Fatal("expected error for wrong password")
		}
		if !errors.Is(err, domain.ErrInvalidCredentials) {
			t.Fatalf("expected ErrInvalidCredentials, got %v", err)
		}
	})

	t.Run("login with non-existent email", func(t *testing.T) {
		svc, _, _ := newAuthService()
		ctx := context.Background()

		_, err := svc.Login(ctx, application.LoginInput{
			Email:    "nobody@example.com",
			Password: "somepassword123",
		})
		if err == nil {
			t.Fatal("expected error for non-existent email")
		}
		if !errors.Is(err, domain.ErrInvalidCredentials) {
			t.Fatalf("expected ErrInvalidCredentials, got %v", err)
		}
	})
}

func TestAuthService_RefreshToken(t *testing.T) {
	t.Run("successful refresh", func(t *testing.T) {
		svc, _, _ := newAuthService()
		ctx := context.Background()

		registerResult, err := svc.Register(ctx, application.RegisterInput{
			Email:         "alice@example.com",
			Username:      "alice",
			Password:      "securepassword123",
			AcceptedTerms: true,
		})
		if err != nil {
			t.Fatalf("register failed: %v", err)
		}

		result, err := svc.RefreshToken(ctx, registerResult.RefreshToken)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if result.AccessToken == "" {
			t.Fatal("expected new access token to be non-empty")
		}
		if result.RefreshToken == "" {
			t.Fatal("expected new refresh token to be non-empty")
		}
	})
}
