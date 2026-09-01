package handlers

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/rs/zerolog"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/chat"
	"github.com/streampulse/backend/internal/infrastructure/observability"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

// Keepalive WebSocket, valeurs du pattern classique gorilla : le serveur
// pingue un peu avant l'expiration du delai de lecture, le pong du client
// repousse ce delai. Un client muet (reseau coupe) est detecte en pongWait.
const (
	chatWriteWait  = 10 * time.Second
	chatPongWait   = 60 * time.Second
	chatPingPeriod = 54 * time.Second
)

var chatUpgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// Pas de verification d'Origin : l'acces est controle par le token JWT
	// (header ou parametre), jamais par un cookie, donc une page tierce ne
	// peut pas se connecter avec la session d'un visiteur (pas de CSRF).
	CheckOrigin: func(r *http.Request) bool { return true },
}

// hijackableWriter rend le ResponseWriter hijackable aux yeux de gorilla :
// les middlewares (logging, metrics, OTEL) empilent des wrappers qui
// n'implementent pas http.Hijacker mais exposent Unwrap ;
// http.ResponseController sait remonter cette chaine jusqu'a la connexion.
type hijackableWriter struct{ http.ResponseWriter }

func (hw hijackableWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	return http.NewResponseController(hw.ResponseWriter).Hijack()
}

type ChatHandler struct {
	streamService *application.StreamService
	hub           *chat.Hub
	logger        zerolog.Logger
	metrics       *observability.Metrics
}

func NewChatHandler(streamService *application.StreamService, hub *chat.Hub, logger zerolog.Logger, metrics *observability.Metrics) *ChatHandler {
	return &ChatHandler{
		streamService: streamService,
		hub:           hub,
		logger:        logger,
		metrics:       metrics,
	}
}

// chatIncoming est la seule trame acceptee d'un client : son texte.
// Tout le reste (id, auteur, horodatage) est pose par le serveur, un client
// ne peut donc pas parler au nom d'un autre.
type chatIncoming struct {
	Text string `json:"text"`
}

// ServeWS connecte le client au salon de chat du flux, en WebSocket.
// Un salon par live : il faut que le flux soit en direct pour entrer, et le
// salon est ferme (participants deconnectes) quand le live s'arrete.
func (h *ChatHandler) ServeWS(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	streamID, err := uuid.Parse(chi.URLParam(r, "id"))
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

	if stream.Status != domain.StreamStatusLive {
		respondError(w, http.StatusBadRequest, "STREAM_NOT_LIVE", "stream is not currently live")
		return
	}

	// Connexion longue : memes raisons que le SSE (voir deadline.go). A faire
	// avant l'upgrade, les deadlines posees par http.Server restent sinon sur
	// la connexion hijackee.
	keepConnectionOpen(w, h.logger)

	conn, err := chatUpgrader.Upgrade(hijackableWriter{w}, r, nil)
	if err != nil {
		// Upgrade a deja repondu au client (400).
		h.logger.Debug().Err(err).Msg("chat websocket upgrade failed")
		return
	}

	userID, _ := uuid.Parse(claims.UserID)
	client := streaming.NewClient(userID, claims.Username)

	h.hub.Join(streamID, client)
	h.metrics.ChatConnections.Inc()
	h.hub.Publish(streamID, chat.NewPresenceMessage(chat.TypeUserJoined, streamID, userID, claims.Username))

	defer func() {
		h.hub.Leave(streamID, client)
		h.metrics.ChatConnections.Dec()
		h.hub.Publish(streamID, chat.NewPresenceMessage(chat.TypeUserLeft, streamID, userID, claims.Username))
		conn.Close()
	}()

	// A l'arret du serveur, la lecture bloquee sur la socket ne regarde pas
	// le contexte : on ferme la connexion pour la debloquer.
	stopAfterFunc := context.AfterFunc(r.Context(), func() { conn.Close() })
	defer stopAfterFunc()

	// Pompe d'ecriture : messages du salon + pings de keepalive. Fermer la
	// connexion en sortie debloque la pompe de lecture ci-dessous, et
	// inversement : les deux pompes meurent toujours ensemble.
	go func() {
		ticker := time.NewTicker(chatPingPeriod)
		defer ticker.Stop()
		defer conn.Close()
		for {
			select {
			case <-client.Done():
				// Salon ferme (fin du live) : on previent le client proprement.
				_ = conn.WriteControl(websocket.CloseMessage,
					websocket.FormatCloseMessage(websocket.CloseGoingAway, "stream ended"),
					time.Now().Add(chatWriteWait))
				return
			case data := <-client.Ch:
				_ = conn.SetWriteDeadline(time.Now().Add(chatWriteWait))
				if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
					return
				}
			case <-ticker.C:
				_ = conn.SetWriteDeadline(time.Now().Add(chatWriteWait))
				if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
					return
				}
			}
		}
	}()

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Str("username", claims.Username).
		Msg("chat client connected")

	// Pompe de lecture, dans la goroutine du handler.
	// 4 KiB suffisent largement pour un message de 500 caracteres en JSON.
	conn.SetReadLimit(4096)
	_ = conn.SetReadDeadline(time.Now().Add(chatPongWait))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(chatPongWait))
	})

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			client.Close()
			return
		}

		var in chatIncoming
		if err := json.Unmarshal(raw, &in); err != nil {
			continue
		}
		text := strings.TrimSpace(in.Text)
		if text == "" || utf8.RuneCountInString(text) > chat.MaxMessageRunes {
			continue
		}

		h.hub.Publish(streamID, chat.NewUserMessage(streamID, userID, claims.Username, text))
		h.metrics.ChatMessagesTotal.Inc()
	}
}
