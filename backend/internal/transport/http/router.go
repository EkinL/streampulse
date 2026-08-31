package http

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/internal/infrastructure/observability"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	"github.com/streampulse/backend/internal/transport/http/handlers"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

type RouterConfig struct {
	AuthService       *application.AuthService
	StreamService     *application.StreamService
	PlaylistService   *application.PlaylistService
	UserService       *application.UserService
	MusicService      *application.MusicService
	FavoriteRepo      domain.FavoriteRepository
	MusicFavoriteRepo domain.MusicFavoriteRepository
	StreamRepo        domain.StreamRepository
	MusicRepo         domain.MusicRepository
	JWTManager        *auth.JWTManager
	Hub               *streaming.Hub
	Logger            zerolog.Logger
	Metrics           *observability.Metrics
	CORSOrigins       string
	RateLimitRPS      float64
	RateLimitBurst    int
	TrustedProxies    []string
	ServiceName       string
}

func NewRouter(cfg RouterConfig) *chi.Mux {
	r := chi.NewRouter()

	// Global middleware
	r.Use(chimiddleware.RequestID)
	// Juste apres RequestID, et avant tout middleware qui ecrit une reponse :
	// un header pose apres WriteHeader est ignore.
	r.Use(middleware.RequestIDHeader)
	// chimiddleware.RealIP est deprecie : il reecrit r.RemoteAddr a partir de
	// X-Forwarded-For / X-Real-IP sans verifier que l'infrastructure les pose
	// reellement, ce qui permet a un client d'usurper son adresse
	// (GHSA-3fxj-6jh8-hvhx). r.RemoteAddr reste donc l'adresse reelle du pair,
	// et le seul composant qui a besoin de l'adresse client - le limiteur de
	// debit - resout lui-meme la question via TRUSTED_PROXIES.
	r.Use(chimiddleware.Recoverer)
	// L'ordre compte : OTELTracing cree le span et le place dans le contexte
	// qu'il passe au handler suivant. Un middleware enregistre AVANT lui ne
	// verrait pas ce span (un contexte ne remonte pas la chaine), donc Logging
	// doit venir apres pour pouvoir loguer le trace_id.
	r.Use(middleware.OTELTracing(cfg.ServiceName))
	r.Use(middleware.Logging(cfg.Logger))
	r.Use(middleware.CORSHandler(cfg.CORSOrigins).Handler)

	rateLimiter := middleware.NewRateLimiter(cfg.RateLimitRPS, cfg.RateLimitBurst, cfg.TrustedProxies...)
	r.Use(rateLimiter.Limit)

	// Handlers
	authMw := middleware.NewAuthMiddleware(cfg.JWTManager)
	healthHandler := handlers.NewHealthHandler()
	docsHandler := handlers.NewDocsHandler()
	authHandler := handlers.NewAuthHandler(cfg.AuthService)
	streamHandler := handlers.NewStreamHandler(cfg.StreamService, cfg.Hub, cfg.Logger, cfg.Metrics)
	playlistHandler := handlers.NewPlaylistHandler(cfg.PlaylistService)
	adminHandler := handlers.NewAdminHandler(cfg.UserService)
	userHandler := handlers.NewUserHandler(cfg.UserService)
	favoritesHandler := handlers.NewFavoritesHandler(cfg.FavoriteRepo, cfg.StreamRepo)
	musicHandler := handlers.NewMusicHandler(cfg.MusicService, cfg.StreamRepo)
	musicFavHandler := handlers.NewMusicFavoritesHandler(cfg.MusicFavoriteRepo, cfg.MusicRepo)

	// Static file serving
	r.Handle("/uploads/*", http.StripPrefix("/uploads/", http.FileServer(http.Dir("./uploads"))))

	// Public routes
	r.Get("/health", healthHandler.Health)

	// API description. Public on purpose: a client that cannot read the
	// contract before authenticating cannot implement authentication.
	r.Get("/openapi.yaml", docsHandler.Spec)
	r.Get("/docs", docsHandler.UI)

	// Auth routes (public)
	r.Route("/auth", func(r chi.Router) {
		r.Post("/register", authHandler.Register)
		r.Post("/login", authHandler.Login)
		r.Post("/refresh", authHandler.Refresh)
	})

	// Streams - public listing
	r.Get("/streams", streamHandler.ListStreams)
	r.Get("/streams/{id}", streamHandler.GetStream)

	// Music - public routes
	r.Get("/music", musicHandler.ListMusic)
	r.Get("/music/search", musicHandler.SearchMusic)
	r.Get("/music/{id}", musicHandler.GetMusic)

	// Global search
	r.Get("/search", musicHandler.GlobalSearch)

	// Authenticated routes
	r.Group(func(r chi.Router) {
		r.Use(authMw.Authenticate)

		// Streams - authenticated
		r.Get("/streams/{id}/listen", streamHandler.Listen)
		r.Get("/streams/{id}/audio", streamHandler.AudioStream)
		r.Get("/streams/{id}/listeners", streamHandler.GetListeners)

		// Compte de la personne connectee : droit d'acces et droit a
		// l'effacement (RGPD, docs/rgpd.md). Ouvert a tout compte
		// authentifie, quel que soit son role.
		r.Get("/users/me", userHandler.Me)
		r.Delete("/users/me", userHandler.DeleteMe)

		// Streams - broadcaster only
		r.Group(func(r chi.Router) {
			r.Use(middleware.RequireRole(domain.RoleBroadcaster))
			r.Post("/streams", streamHandler.CreateStream)
			r.Put("/streams/{id}", streamHandler.UpdateStream)
			r.Post("/streams/{id}/start", streamHandler.StartStream)
			r.Post("/streams/{id}/stop", streamHandler.StopStream)
			r.Post("/streams/{id}/broadcast", streamHandler.Broadcast)

			// Music - broadcaster only
			r.Post("/music", musicHandler.UploadMusic)
			r.Put("/music/{id}", musicHandler.UpdateMusic)
			r.Delete("/music/{id}", musicHandler.DeleteMusic)
		})

		// Music favorites
		r.Get("/music/favorites", musicFavHandler.ListFavorites)
		r.Get("/music/favorites/ids", musicFavHandler.ListFavoriteIDs)
		r.Post("/music/{id}/favorite", musicFavHandler.AddFavorite)
		r.Delete("/music/{id}/favorite", musicFavHandler.RemoveFavorite)

		// Favorites
		r.Route("/favorites", func(r chi.Router) {
			r.Get("/", favoritesHandler.ListFavorites)
			r.Post("/{streamId}", favoritesHandler.AddFavorite)
			r.Delete("/{streamId}", favoritesHandler.RemoveFavorite)
		})

		// Playlists
		r.Route("/playlists", func(r chi.Router) {
			r.Get("/", playlistHandler.ListPlaylists)
			r.Post("/", playlistHandler.CreatePlaylist)
			r.Get("/{id}", playlistHandler.GetPlaylist)
			r.Put("/{id}", playlistHandler.UpdatePlaylist)
			r.Delete("/{id}", playlistHandler.DeletePlaylist)
			r.Post("/{id}/tracks", playlistHandler.AddTrack)
			r.Put("/{id}/tracks", playlistHandler.ReorderTracks)
			r.Delete("/{id}/tracks/{trackId}", playlistHandler.RemoveTrack)
		})

		// Admin routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.RequireRole(domain.RoleAdmin))
			r.Get("/admin/users", adminHandler.ListUsers)
			r.Put("/admin/users/{id}/role", adminHandler.UpdateUserRole)
			r.Delete("/admin/users/{id}", adminHandler.DeleteUser)

			// Prometheus metrics: admin only, as required by docs/api.md.
			// Prometheus itself scrapes the internal listener started in
			// cmd/server/main.go, not this route.
			r.Handle("/metrics", promhttp.Handler())
		})
	})

	return r
}
