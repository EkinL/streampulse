package application

import (
	"context"
	"time"

	"github.com/rs/zerolog"
	"github.com/streampulse/backend/internal/domain"
)

// PurgeExpiredRefreshTokens supprime les refresh tokens expires, tout de
// suite puis a chaque intervalle, jusqu'a l'annulation du contexte.
//
// Un refresh token expire est deja refuse a la lecture (FindByHash) ; cette
// purge n'est donc pas une question de securite mais de retention : on ne
// conserve pas en base des jetons rattaches a une personne au-dela de leur
// utilite (docs/rgpd.md). Une erreur est loguee et n'arrete pas la boucle,
// la passe suivante rattrapera.
func PurgeExpiredRefreshTokens(ctx context.Context, repo domain.RefreshTokenRepository, interval time.Duration, logger zerolog.Logger) {
	purge := func() {
		// Deadline par passe : une base qui ne repond plus ne doit pas bloquer
		// la boucle, la passe suivante retentera.
		c, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		if err := repo.DeleteExpired(c); err != nil {
			logger.Warn().Err(err).Msg("failed to purge expired refresh tokens")
		}
	}

	purge()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			purge()
		}
	}
}
