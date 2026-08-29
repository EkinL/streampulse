package main

import (
	"context"
	"crypto/tls"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/internal/infrastructure/config"
	"github.com/streampulse/backend/internal/infrastructure/filestore"
	"github.com/streampulse/backend/internal/infrastructure/observability"
	"github.com/streampulse/backend/internal/infrastructure/postgres"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	transport "github.com/streampulse/backend/internal/transport/http"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Load .env file if exists
	config.LoadFromEnvFile(".env")

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		panic("failed to load config: " + err.Error())
	}

	// Initialize logger. Le format vient de LOG_FORMAT, pas de APP_ENV :
	// voir observability.NewLogger.
	logger := observability.NewLogger(cfg.LogLevel, cfg.LogFormat, cfg.OTELServiceName)

	logger.Info().
		Str("env", cfg.AppEnv).
		Str("log_format", cfg.LogFormat).
		Int("port", cfg.Port).
		Msg("starting streampulse api")

	// Initialize OpenTelemetry tracer
	tp, err := observability.InitTracer(ctx, cfg.OTELEndpoint, cfg.OTELServiceName)
	if err != nil {
		logger.Warn().Err(err).Msg("failed to initialize otel tracer, continuing without tracing")
	} else {
		defer func() {
			shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer shutdownCancel()
			if err := tp.Shutdown(shutdownCtx); err != nil {
				logger.Error().Err(err).Msg("failed to shut down otel tracer")
			}
		}()
	}

	// Initialize metrics
	metrics := observability.NewMetrics()

	// Initialize database
	pool, err := postgres.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Fatal().Err(err).Msg("failed to connect to database")
	}
	defer pool.Close()

	// Run migrations
	if err := postgres.RunMigrations(ctx, pool, logger); err != nil {
		logger.Fatal().Err(err).Msg("failed to run migrations")
	}
	logger.Info().Msg("database migrations completed")

	// Initialize repositories
	userRepo := postgres.NewUserRepo(pool)
	streamRepo := postgres.NewStreamRepo(pool)
	playlistRepo := postgres.NewPlaylistRepo(pool)
	refreshTokenRepo := postgres.NewRefreshTokenRepo(pool)
	favoriteRepo := postgres.NewFavoriteRepo(pool)
	musicRepo := postgres.NewMusicRepo(pool)
	musicFavoriteRepo := postgres.NewMusicFavoriteRepo(pool)

	// Initialize file store. L'URL publique suit PUBLIC_BASE_URL, ou a defaut
	// le port et l'activation de TLS : un fichier uploade doit rester
	// joignable quand le serveur passe en HTTPS.
	fileStore := filestore.NewFileStore("./uploads", cfg.PublicBaseURL()+"/uploads")

	// Initialize JWT manager
	jwtManager := auth.NewJWTManager(cfg.JWTSecret, cfg.JWTExpiry, cfg.JWTRefreshExpiry)

	// Initialize streaming hub
	hub := streaming.NewHub(logger)
	hub.OnListenerChange = func(streamID uuid.UUID, count int) {
		// Hors requete (le hub appelle ca depuis Broadcast/Unregister), donc pas
		// de contexte parent : on en pose un borne, sinon une base qui ne
		// repond plus laisserait s'accumuler une goroutine par changement.
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := streamRepo.UpdateListenerCount(ctx, streamID, count); err != nil {
				logger.Warn().Err(err).Str("stream_id", streamID.String()).Msg("failed to update listener count")
			}
		}()
	}

	// Contexte de base des requetes HTTP et des taches de fond qui touchent
	// la base : annule explicitement a l'arret, AVANT pool.Close (differe),
	// pour liberer les connexions longues (SSE, audio, broadcast) et arreter
	// la purge sans qu'elle tombe sur un pool ferme.
	requestsCtx, cancelRequests := context.WithCancel(ctx)
	defer cancelRequests()

	// Politique de retention (docs/rgpd.md) : les refresh tokens expires
	// sont purges a intervalle regulier au lieu de s'accumuler en base.
	go application.PurgeExpiredRefreshTokens(requestsCtx, refreshTokenRepo, cfg.RefreshTokenPurgeInterval, logger)

	// Initialize services
	authService := application.NewAuthService(userRepo, refreshTokenRepo, jwtManager)
	streamService := application.NewStreamService(streamRepo, hub)
	playlistService := application.NewPlaylistService(playlistRepo)
	userService := application.NewUserService(userRepo, streamRepo, hub)
	musicService := application.NewMusicService(musicRepo, fileStore)

	// Initialize router
	router := transport.NewRouter(transport.RouterConfig{
		AuthService:       authService,
		StreamService:     streamService,
		PlaylistService:   playlistService,
		UserService:       userService,
		MusicService:      musicService,
		FavoriteRepo:      favoriteRepo,
		MusicFavoriteRepo: musicFavoriteRepo,
		StreamRepo:        streamRepo,
		MusicRepo:         musicRepo,
		JWTManager:        jwtManager,
		Hub:               hub,
		Logger:            logger,
		Metrics:           metrics,
		CORSOrigins:       cfg.CORSAllowedOrigins,
		RateLimitRPS:      cfg.RateLimitRPS,
		RateLimitBurst:    cfg.RateLimitBurst,
		ServiceName:       cfg.OTELServiceName,
	})

	// Start server. Les timeouts sont globaux ; les trois handlers de flux
	// les levent pour leur seule connexion via http.ResponseController
	// (voir handlers/deadline.go et docs/ADR/005-http-timeouts.md).
	srv := &http.Server{
		Addr:              cfg.Addr(),
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second, // slowloris
		ReadTimeout:       cfg.HTTPReadTimeout,
		WriteTimeout:      cfg.HTTPWriteTimeout,
		IdleTimeout:       cfg.HTTPIdleTimeout,
		BaseContext:       func(net.Listener) context.Context { return requestsCtx },
		// N'a d'effet qu'avec ListenAndServeTLS : TLS 1.0 et 1.1 sont
		// obsoletes (RFC 8996).
		TLSConfig: &tls.Config{MinVersion: tls.VersionTLS12},
	}

	// Internal metrics server. Prometheus scrapes this listener from
	// inside the Docker network; the public /metrics route on the main
	// router is admin-only (see transport/http/router.go).
	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.Handler())
	metricsSrv := &http.Server{
		Addr:         cfg.MetricsAddr(),
		Handler:      metricsMux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	// TLS natif si TLS_CERT_FILE et TLS_KEY_FILE sont renseignes, sinon en
	// clair derriere un reverse proxy qui termine TLS (docs/deployment.md).
	go func() {
		var err error
		if cfg.TLSEnabled() {
			logger.Info().Str("addr", cfg.Addr()).Msg("https server started")
			err = srv.ListenAndServeTLS(cfg.TLSCertFile, cfg.TLSKeyFile)
		} else {
			logger.Info().Str("addr", cfg.Addr()).Msg("http server started")
			err = srv.ListenAndServe()
		}
		if err != nil && err != http.ErrServerClosed {
			logger.Fatal().Err(err).Msg("http server error")
		}
	}()

	go func() {
		logger.Info().Str("addr", cfg.MetricsAddr()).Msg("metrics server started")
		if err := metricsSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal().Err(err).Msg("metrics server error")
		}
	}()

	<-quit
	logger.Info().Msg("shutting down server...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer shutdownCancel()

	if err := metricsSrv.Shutdown(shutdownCtx); err != nil {
		logger.Error().Err(err).Msg("metrics server forced to shutdown")
	}

	// On coupe le contexte des requetes en cours avant Shutdown : les boucles
	// SSE / audio / broadcast sortent sur r.Context().Done(), les connexions
	// passent idle et Shutdown rend la main tout de suite.
	cancelRequests()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Fatal().Err(err).Msg("server forced to shutdown")
	}

	logger.Info().Msg("server stopped")
}
