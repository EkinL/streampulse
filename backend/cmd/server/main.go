package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/google/uuid"
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

	// Initialize logger
	var logger = observability.NewLogger(cfg.LogLevel, cfg.OTELServiceName)
	if !cfg.IsDevelopment() {
		logger = observability.NewProductionLogger(cfg.LogLevel, cfg.OTELServiceName)
	}

	logger.Info().Str("env", cfg.AppEnv).Int("port", cfg.Port).Msg("starting streampulse api")

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

	// Initialize file store
	fileStore := filestore.NewFileStore("./uploads", "http://localhost"+cfg.Addr()+"/uploads")

	// Initialize JWT manager
	jwtManager := auth.NewJWTManager(cfg.JWTSecret, cfg.JWTExpiry, cfg.JWTRefreshExpiry)

	// Initialize streaming hub
	hub := streaming.NewHub(logger)
	hub.OnListenerChange = func(streamID uuid.UUID, count int) {
		go func() {
			_ = streamRepo.UpdateListenerCount(context.Background(), streamID, count)
		}()
	}

	// Initialize services
	authService := application.NewAuthService(userRepo, refreshTokenRepo, jwtManager)
	streamService := application.NewStreamService(streamRepo, hub)
	playlistService := application.NewPlaylistService(playlistRepo)
	userService := application.NewUserService(userRepo)
	musicService := application.NewMusicService(musicRepo, fileStore)

	// Initialize router
	router := transport.NewRouter(transport.RouterConfig{
		AuthService:     authService,
		StreamService:   streamService,
		PlaylistService: playlistService,
		UserService:     userService,
		MusicService:    musicService,
		FavoriteRepo:         favoriteRepo,
		MusicFavoriteRepo:   musicFavoriteRepo,
		StreamRepo:           streamRepo,
		MusicRepo:            musicRepo,
		JWTManager:      jwtManager,
		Hub:             hub,
		Logger:          logger,
		Metrics:         metrics,
		CORSOrigins:     cfg.CORSAllowedOrigins,
		RateLimitRPS:    cfg.RateLimitRPS,
		RateLimitBurst:  cfg.RateLimitBurst,
		ServiceName:     cfg.OTELServiceName,
	})

	// Start server
	srv := &http.Server{
		Addr:         cfg.Addr(),
		Handler:      router,
		ReadTimeout:  0, // Disabled for broadcast + SSE streaming
		WriteTimeout: 0, // Disabled for SSE streaming
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		logger.Info().Str("addr", cfg.Addr()).Msg("http server started")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal().Err(err).Msg("http server error")
		}
	}()

	<-quit
	logger.Info().Msg("shutting down server...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Fatal().Err(err).Msg("server forced to shutdown")
	}

	logger.Info().Msg("server stopped")
}
