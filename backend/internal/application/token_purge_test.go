package application_test

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
)

// countingTokenRepo compte les purges et peut les faire echouer.
type countingTokenRepo struct {
	domain.RefreshTokenRepository
	calls atomic.Int32
	fail  bool
}

func (r *countingTokenRepo) DeleteExpired(context.Context) error {
	r.calls.Add(1)
	if r.fail {
		return errors.New("base injoignable")
	}
	return nil
}

func (r *countingTokenRepo) DeleteByUserID(context.Context, uuid.UUID) error { return nil }

func TestPurgeExpiredRefreshTokens(t *testing.T) {
	t.Run("purge au demarrage puis a chaque intervalle", func(t *testing.T) {
		repo := &countingTokenRepo{}
		ctx, cancel := context.WithCancel(context.Background())
		done := make(chan struct{})
		go func() {
			application.PurgeExpiredRefreshTokens(ctx, repo, 5*time.Millisecond, zerolog.Nop())
			close(done)
		}()

		deadline := time.Now().Add(2 * time.Second)
		for repo.calls.Load() < 3 && time.Now().Before(deadline) {
			time.Sleep(time.Millisecond)
		}
		cancel()
		<-done
		if got := repo.calls.Load(); got < 3 {
			t.Fatalf("purges = %d, attendu au moins 3 (une immediate + les ticks)", got)
		}
	})

	t.Run("une erreur n'arrete pas la boucle", func(t *testing.T) {
		repo := &countingTokenRepo{fail: true}
		ctx, cancel := context.WithCancel(context.Background())
		done := make(chan struct{})
		go func() {
			application.PurgeExpiredRefreshTokens(ctx, repo, 5*time.Millisecond, zerolog.Nop())
			close(done)
		}()

		deadline := time.Now().Add(2 * time.Second)
		for repo.calls.Load() < 2 && time.Now().Before(deadline) {
			time.Sleep(time.Millisecond)
		}
		cancel()
		<-done
		if got := repo.calls.Load(); got < 2 {
			t.Fatalf("purges = %d : la boucle doit continuer apres une erreur", got)
		}
	})

	t.Run("s'arrete a l'annulation du contexte", func(t *testing.T) {
		repo := &countingTokenRepo{}
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		done := make(chan struct{})
		go func() {
			application.PurgeExpiredRefreshTokens(ctx, repo, time.Hour, zerolog.Nop())
			close(done)
		}()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Fatal("la boucle ne s'est pas arretee sur un contexte annule")
		}
	})
}
