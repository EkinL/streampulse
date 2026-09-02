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

// fakeOAuthVerifier rend l'identite programmee, ou l'erreur : le service se
// teste sans reseau, la verification cryptographique a ses propres tests
// dans infrastructure/auth.
type fakeOAuthVerifier struct {
	identity *domain.OAuthIdentity
	err      error
}

func (f *fakeOAuthVerifier) Verify(_ context.Context, _, _ string) (*domain.OAuthIdentity, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.identity, nil
}

func newOAuthAuthService(verifier domain.OAuthVerifier) (*application.AuthService, *testutil.MockUserRepo) {
	userRepo := testutil.NewMockUserRepo()
	refreshTokenRepo := testutil.NewMockRefreshTokenRepo()
	jwtManager := auth.NewJWTManager("test-secret-key-for-unit-tests", 15*time.Minute, 168*time.Hour)
	return application.NewAuthService(userRepo, refreshTokenRepo, jwtManager, verifier), userRepo
}

func TestAuthService_LoginWithOAuth(t *testing.T) {
	googleIdentity := &domain.OAuthIdentity{
		Provider:      domain.ProviderGoogle,
		Subject:       "google-sub-123",
		Email:         "alice@example.com",
		EmailVerified: true,
		Name:          "Alice",
	}

	t.Run("first sign-in creates a user account", func(t *testing.T) {
		svc, userRepo := newOAuthAuthService(&fakeOAuthVerifier{identity: googleIdentity})

		result, err := svc.LoginWithOAuth(context.Background(), application.OAuthLoginInput{
			Provider: domain.ProviderGoogle,
			IDToken:  "raw-token",
		})
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if result.AccessToken == "" || result.RefreshToken == "" {
			t.Fatal("expected a token pair")
		}
		if result.User.Role != domain.RoleUser {
			t.Fatalf("expected role user, got %s", result.User.Role)
		}
		if result.User.Username != "Alice" {
			t.Fatalf("expected username Alice, got %s", result.User.Username)
		}
		if result.User.PasswordHash != "" {
			t.Fatal("social account must have no password hash")
		}
		if result.User.TermsAcceptedAt.IsZero() {
			t.Fatal("expected terms acceptance to be timestamped")
		}

		stored, err := userRepo.FindByProviderSubject(context.Background(), domain.ProviderGoogle, "google-sub-123")
		if err != nil {
			t.Fatalf("expected user stored under provider subject, got %v", err)
		}
		if stored.Email != "alice@example.com" {
			t.Fatalf("unexpected stored email %s", stored.Email)
		}
	})

	t.Run("second sign-in logs into the same account", func(t *testing.T) {
		svc, _ := newOAuthAuthService(&fakeOAuthVerifier{identity: googleIdentity})
		ctx := context.Background()

		first, err := svc.LoginWithOAuth(ctx, application.OAuthLoginInput{Provider: domain.ProviderGoogle, IDToken: "t1"})
		if err != nil {
			t.Fatalf("first login: %v", err)
		}
		second, err := svc.LoginWithOAuth(ctx, application.OAuthLoginInput{Provider: domain.ProviderGoogle, IDToken: "t2"})
		if err != nil {
			t.Fatalf("second login: %v", err)
		}
		if first.User.ID != second.User.ID {
			t.Fatal("expected both logins to land on the same account")
		}
	})

	t.Run("verified email links to existing password account", func(t *testing.T) {
		svc, _ := newOAuthAuthService(&fakeOAuthVerifier{identity: googleIdentity})
		ctx := context.Background()

		registered, err := svc.Register(ctx, application.RegisterInput{
			Email:         "alice@example.com",
			Username:      "alice",
			Password:      "securepassword123",
			AcceptedTerms: true,
		})
		if err != nil {
			t.Fatalf("register: %v", err)
		}

		result, err := svc.LoginWithOAuth(ctx, application.OAuthLoginInput{Provider: domain.ProviderGoogle, IDToken: "t"})
		if err != nil {
			t.Fatalf("expected linking to succeed, got %v", err)
		}
		if result.User.ID != registered.User.ID {
			t.Fatal("expected the existing account, not a new one")
		}
		if result.User.ProviderSubject != "google-sub-123" {
			t.Fatal("expected the provider subject to be linked")
		}
	})

	t.Run("unverified email does not link", func(t *testing.T) {
		unverified := *googleIdentity
		unverified.EmailVerified = false
		svc, _ := newOAuthAuthService(&fakeOAuthVerifier{identity: &unverified})
		ctx := context.Background()

		if _, err := svc.Register(ctx, application.RegisterInput{
			Email:         "alice@example.com",
			Username:      "alice",
			Password:      "securepassword123",
			AcceptedTerms: true,
		}); err != nil {
			t.Fatalf("register: %v", err)
		}

		_, err := svc.LoginWithOAuth(ctx, application.OAuthLoginInput{Provider: domain.ProviderGoogle, IDToken: "t"})
		if !errors.Is(err, domain.ErrAlreadyExists) {
			t.Fatalf("expected ErrAlreadyExists, got %v", err)
		}
	})

	t.Run("invalid identity token", func(t *testing.T) {
		svc, _ := newOAuthAuthService(&fakeOAuthVerifier{err: domain.ErrTokenInvalid})

		_, err := svc.LoginWithOAuth(context.Background(), application.OAuthLoginInput{Provider: domain.ProviderGoogle, IDToken: "bad"})
		if !errors.Is(err, domain.ErrTokenInvalid) {
			t.Fatalf("expected ErrTokenInvalid, got %v", err)
		}
	})

	t.Run("identity without email is rejected", func(t *testing.T) {
		noEmail := *googleIdentity
		noEmail.Email = ""
		svc, _ := newOAuthAuthService(&fakeOAuthVerifier{identity: &noEmail})

		_, err := svc.LoginWithOAuth(context.Background(), application.OAuthLoginInput{Provider: domain.ProviderGoogle, IDToken: "t"})
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}
	})

	t.Run("no verifier configured", func(t *testing.T) {
		svc, _ := newOAuthAuthService(nil)

		_, err := svc.LoginWithOAuth(context.Background(), application.OAuthLoginInput{Provider: domain.ProviderGoogle, IDToken: "t"})
		if !errors.Is(err, domain.ErrProviderNotConfigured) {
			t.Fatalf("expected ErrProviderNotConfigured, got %v", err)
		}
	})

	t.Run("missing provider or token", func(t *testing.T) {
		svc, _ := newOAuthAuthService(&fakeOAuthVerifier{identity: googleIdentity})

		_, err := svc.LoginWithOAuth(context.Background(), application.OAuthLoginInput{})
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}
	})

	t.Run("password login stays closed for a social account", func(t *testing.T) {
		svc, _ := newOAuthAuthService(&fakeOAuthVerifier{identity: googleIdentity})
		ctx := context.Background()

		if _, err := svc.LoginWithOAuth(ctx, application.OAuthLoginInput{Provider: domain.ProviderGoogle, IDToken: "t"}); err != nil {
			t.Fatalf("oauth login: %v", err)
		}

		_, err := svc.Login(ctx, application.LoginInput{Email: "alice@example.com", Password: "anything-at-all"})
		if !errors.Is(err, domain.ErrInvalidCredentials) {
			t.Fatalf("expected ErrInvalidCredentials, got %v", err)
		}
	})
}
