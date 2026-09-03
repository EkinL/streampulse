package handlers

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

// Taille maximale d'une trame audio. La console envoie des tampons de
// quelques Ko (PCM16 16 kHz mono) : 64 KiB laisse de la marge sans permettre
// a un client de faire gonfler la memoire du serveur.
const broadcastMaxFrame = 64 << 10

var broadcastUpgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 1024,
	// Comme le chat : l'acces est controle par le token JWT, jamais par un
	// cookie, donc pas de surface CSRF a fermer par l'Origin.
	CheckOrigin: func(r *http.Request) bool { return true },
}

// broadcastAllowed fait les verifications communes aux deux entrees d'ingest
// (POST chunke et WebSocket) : appelant authentifie, id valide, flux existant,
// appelant proprietaire, flux en direct. Quand ok est faux, la reponse
// d'erreur a deja ete ecrite.
func (h *StreamHandler) broadcastAllowed(w http.ResponseWriter, r *http.Request) (streamID, ownerID uuid.UUID, ok bool) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	var err error
	streamID, err = uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid stream id")
		return
	}

	stream, err := h.streamService.GetStream(r.Context(), streamID)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "stream not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to get stream")
		return
	}

	ownerID, _ = uuid.Parse(claims.UserID)
	if stream.OwnerID != ownerID {
		respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this stream")
		return
	}

	if stream.Status != domain.StreamStatusLive {
		respondError(w, http.StatusBadRequest, "STREAM_NOT_LIVE", "stream must be started first")
		return
	}

	return streamID, ownerID, true
}

// BroadcastWS est l'equivalent WebSocket de Broadcast : chaque trame binaire
// recue est un chunk audio, diffuse tel quel aux auditeurs du flux.
//
// Le POST chunke convient a l'app mobile (dart:io ecrit le corps au fil de
// l'eau) mais pas a la console web : dans un navigateur, XMLHttpRequest
// accumule tout le corps en memoire et ne l'envoie qu'une fois le flux
// termine, c'est-a-dire a la fin du live. Les auditeurs restaient sur
// "Waiting for audio". Un WebSocket part trame par trame, dans tous les
// navigateurs et a travers le reverse proxy.
//
// Memes conditions que le POST (proprietaire, flux live) et meme preuve de
// vie : une connexion fermee sans remplacement dans le delai de grace arrete
// le direct.
func (h *StreamHandler) BroadcastWS(w http.ResponseWriter, r *http.Request) {
	streamID, ownerID, ok := h.broadcastAllowed(w, r)
	if !ok {
		return
	}

	// Connexion longue : a faire avant l'upgrade, les deadlines posees par
	// http.Server resteraient sinon sur la connexion hijackee.
	keepConnectionOpen(w, h.logger)

	conn, err := broadcastUpgrader.Upgrade(hijackableWriter{w}, r, nil)
	if err != nil {
		// Upgrade a deja repondu au client (400).
		h.logger.Debug().Err(err).Msg("broadcast websocket upgrade failed")
		return
	}
	defer func() { _ = conn.Close() }()

	gen := h.broadcasterConnected(streamID)
	defer h.broadcasterGone(streamID, gen, ownerID)

	// A l'arret du serveur, la lecture bloquee sur la socket ne regarde pas
	// le contexte : on ferme la connexion pour la debloquer.
	stopAfterFunc := context.AfterFunc(r.Context(), func() { _ = conn.Close() })
	defer stopAfterFunc()

	// Keepalive, memes reglages que le chat : le serveur pingue, et le pong
	// comme n'importe quelle trame audio repousse le delai de lecture. Un
	// diffuseur dont le reseau est tombe est detecte en chatPongWait, puis le
	// delai de grace s'applique.
	done := make(chan struct{})
	defer close(done)
	go func() {
		ticker := time.NewTicker(chatPingPeriod)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				return
			case <-ticker.C:
				if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(chatWriteWait)); err != nil {
					return
				}
			}
		}
	}()

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Msg("broadcaster connected over websocket, reading audio frames")

	conn.SetReadLimit(broadcastMaxFrame)
	_ = conn.SetReadDeadline(time.Now().Add(chatPongWait))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(chatPongWait))
	})

	totalBytes := 0
	for {
		messageType, data, err := conn.ReadMessage()
		if err != nil {
			// Fermeture propre (antenne coupee) ou coupure reseau : dans les
			// deux cas le direct ne survit que le temps du delai de grace.
			if r.Context().Err() == nil && !websocket.IsCloseError(err,
				websocket.CloseNormalClosure, websocket.CloseGoingAway, websocket.CloseNoStatusReceived) {
				h.logger.Debug().Err(err).Str("stream_id", streamID.String()).Msg("broadcast websocket read ended")
			}
			break
		}
		_ = conn.SetReadDeadline(time.Now().Add(chatPongWait))
		if messageType != websocket.BinaryMessage || len(data) == 0 {
			continue
		}
		h.hub.Broadcast(streamID, data)
		totalBytes += len(data)
		h.metrics.StreamBytesSentTotal.Add(float64(len(data)))
	}

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Int("total_bytes", totalBytes).
		Msg("broadcaster disconnected")
}
