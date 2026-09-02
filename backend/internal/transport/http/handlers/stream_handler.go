package handlers

import (
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/rs/zerolog"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/chat"
	"github.com/streampulse/backend/internal/infrastructure/observability"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	"github.com/streampulse/backend/internal/transport/http/dto"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

type StreamHandler struct {
	streamService *application.StreamService
	hub           *streaming.Hub
	chatHub       *chat.Hub
	logger        zerolog.Logger
	metrics       *observability.Metrics
}

func NewStreamHandler(streamService *application.StreamService, hub *streaming.Hub, chatHub *chat.Hub, logger zerolog.Logger, metrics *observability.Metrics) *StreamHandler {
	return &StreamHandler{
		streamService: streamService,
		hub:           hub,
		chatHub:       chatHub,
		logger:        logger,
		metrics:       metrics,
	}
}

func (h *StreamHandler) ListStreams(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = 20
	}

	streams, total, err := h.streamService.ListStreams(r.Context(), page, perPage)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list streams")
		return
	}

	items := make([]dto.StreamResponse, 0, len(streams))
	for _, s := range streams {
		items = append(items, toStreamResponse(&s))
	}
	respondPaginated(w, items, page, perPage, total)
}

func (h *StreamHandler) CreateStream(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	var req dto.CreateStreamRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	ownerID, _ := uuid.Parse(claims.UserID)
	stream, err := h.streamService.CreateStream(r.Context(), application.CreateStreamInput{
		Title:       req.Title,
		Description: req.Description,
		Format:      req.Format,
		OwnerID:     ownerID,
	})
	if err != nil {
		if errors.Is(err, domain.ErrInvalidInput) {
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create stream")
		return
	}

	respondJSON(w, http.StatusCreated, toStreamResponse(stream))
}

func (h *StreamHandler) UpdateStream(w http.ResponseWriter, r *http.Request) {
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

	var req dto.UpdateStreamRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	ownerID, _ := uuid.Parse(claims.UserID)
	stream, err := h.streamService.UpdateStream(r.Context(), streamID, ownerID, req.Title, req.Description)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "stream not found")
			return
		}
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this stream")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update stream")
		return
	}

	respondJSON(w, http.StatusOK, toStreamResponse(stream))
}

func (h *StreamHandler) GetStream(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid stream id")
		return
	}

	stream, err := h.streamService.GetStream(r.Context(), id)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "stream not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to get stream")
		return
	}

	respondJSON(w, http.StatusOK, toStreamResponse(stream))
}

func (h *StreamHandler) Listen(w http.ResponseWriter, r *http.Request) {
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

	flusher, ok := w.(http.Flusher)
	if !ok {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "streaming not supported")
		return
	}

	// Connexion longue : on leve les timeouts globaux du serveur pour cette
	// connexion uniquement. La sortie reste pilotee par r.Context() (client
	// parti, serveur en arret) et client.Done() (stream ferme).
	keepConnectionOpen(w, h.logger)

	userID, _ := uuid.Parse(claims.UserID)
	client := streaming.NewClient(userID, claims.Username)
	h.hub.Register(streamID, client)
	h.metrics.ActiveListeners.Inc()

	// reason est la cause de sortie de la boucle de lecture ci-dessous, lue
	// par le defer une fois la fonction sur le point de retourner. "client"
	// est le cas par defaut : le contexte de la requete s'annule aussi bien
	// quand l'auditeur se deconnecte que quand le serveur s'arrete, ce qui
	// est la sortie normale.
	reason := observability.DisconnectReasonClient
	defer func() {
		h.hub.Unregister(streamID, client)
		h.metrics.ActiveListeners.Dec()
		h.metrics.StreamDisconnections.WithLabelValues(reason).Inc()
		h.metrics.ListenerSessions.Inc()
		if client.Dropped() > 0 {
			h.metrics.SessionsWithChunkLoss.Inc()
		}
	}()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	// Send initial connected event
	if _, err := fmt.Fprintf(w, "event: connected\ndata: {\"status\":\"connected\",\"stream_id\":\"%s\"}\n\n", streamID); err != nil {
		reason = observability.DisconnectReasonAbrupt
		return
	}
	flusher.Flush()

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Str("client_id", client.ID.String()).
		Str("username", claims.Username).
		Msg("client connected to stream")

	for {
		select {
		case <-r.Context().Done():
			return
		case <-client.Done():
			reason = observability.DisconnectReasonStreamClosed
			return
		case data, ok := <-client.Ch:
			if !ok {
				reason = observability.DisconnectReasonStreamClosed
				return
			}
			encoded := base64.StdEncoding.EncodeToString(data)
			if _, err := fmt.Fprintf(w, "data: %s\n\n", encoded); err != nil {
				reason = observability.DisconnectReasonAbrupt
				h.logger.Debug().Err(err).
					Str("client_id", client.ID.String()).
					Msg("sse write failed, closing stream")
				return
			}
			flusher.Flush()
			h.metrics.StreamBytesSentTotal.Add(float64(len(data)))
		}
	}
}

// AudioStream streams raw audio bytes to the client (no SSE framing).
// This is the endpoint used by mobile audio players that need raw audio data.
func (h *StreamHandler) AudioStream(w http.ResponseWriter, r *http.Request) {
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

	flusher, ok := w.(http.Flusher)
	if !ok {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "streaming not supported")
		return
	}

	// Connexion longue : on leve les timeouts globaux du serveur pour cette
	// connexion uniquement. La sortie reste pilotee par r.Context() (client
	// parti, serveur en arret) et client.Done() (stream ferme).
	keepConnectionOpen(w, h.logger)

	userID, _ := uuid.Parse(claims.UserID)
	client := streaming.NewClient(userID, claims.Username)
	h.hub.Register(streamID, client)
	h.metrics.ActiveListeners.Inc()

	reason := observability.DisconnectReasonClient
	defer func() {
		h.hub.Unregister(streamID, client)
		h.metrics.ActiveListeners.Dec()
		h.metrics.StreamDisconnections.WithLabelValues(reason).Inc()
		h.metrics.ListenerSessions.Inc()
		if client.Dropped() > 0 {
			h.metrics.SessionsWithChunkLoss.Inc()
		}
	}()

	// Stream raw audio bytes
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Transfer-Encoding", "chunked")
	w.Header().Set("X-Accel-Buffering", "no")
	flusher.Flush()

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Str("username", claims.Username).
		Msg("audio stream client connected")

	for {
		select {
		case <-r.Context().Done():
			return
		case <-client.Done():
			reason = observability.DisconnectReasonStreamClosed
			return
		case data, ok := <-client.Ch:
			if !ok {
				reason = observability.DisconnectReasonStreamClosed
				return
			}
			if _, err := w.Write(data); err != nil {
				reason = observability.DisconnectReasonAbrupt
				return
			}
			flusher.Flush()
			h.metrics.StreamBytesSentTotal.Add(float64(len(data)))
		}
	}
}

func (h *StreamHandler) StartStream(w http.ResponseWriter, r *http.Request) {
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

	ownerID, _ := uuid.Parse(claims.UserID)
	if err := h.streamService.StartStream(r.Context(), streamID, ownerID); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "stream not found")
			return
		}
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this stream")
			return
		}
		if errors.Is(err, domain.ErrStreamAlreadyLive) {
			respondError(w, http.StatusConflict, "CONFLICT", "stream is already live")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to start stream")
		return
	}

	h.metrics.ActiveStreams.Inc()
	respondJSON(w, http.StatusOK, map[string]string{"status": "live"})
}

// Broadcast accepts a long-lived POST with chunked audio data from the broadcaster.
// The body is read continuously and each chunk is broadcast to all connected listeners.
func (h *StreamHandler) Broadcast(w http.ResponseWriter, r *http.Request) {
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

	ownerID, _ := uuid.Parse(claims.UserID)
	if stream.OwnerID != ownerID {
		respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this stream")
		return
	}

	if stream.Status != domain.StreamStatusLive {
		respondError(w, http.StatusBadRequest, "STREAM_NOT_LIVE", "stream must be started first")
		return
	}

	// Le diffuseur pousse son audio dans le corps de la requete pendant
	// toute la duree du live : le ReadTimeout global ne peut pas s'appliquer.
	// En contrepartie on rattache la lecture au contexte, sinon un diffuseur
	// silencieux bloquerait l'arret du serveur.
	keepConnectionOpen(w, h.logger)
	defer unblockReadOnCancel(r.Context(), w)()

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Msg("broadcaster connected, reading audio chunks")

	// Read audio chunks from body and broadcast to all listeners
	buf := make([]byte, 4096)
	totalBytes := 0
	for {
		n, err := r.Body.Read(buf)
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			h.hub.Broadcast(streamID, chunk)
			totalBytes += n
			h.metrics.StreamBytesSentTotal.Add(float64(n))
		}
		if err != nil {
			if err != io.EOF && r.Context().Err() == nil {
				h.logger.Error().Err(err).Str("stream_id", streamID.String()).Msg("broadcast read error")
			}
			break
		}
	}

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Int("total_bytes", totalBytes).
		Msg("broadcaster disconnected")

	// Don't write response - connection was streaming
}

func (h *StreamHandler) StopStream(w http.ResponseWriter, r *http.Request) {
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

	ownerID, _ := uuid.Parse(claims.UserID)
	if err := h.streamService.StopStream(r.Context(), streamID, ownerID); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "stream not found")
			return
		}
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this stream")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to stop stream")
		return
	}

	// Le live est fini : le salon de chat associe l'est aussi, ses
	// participants sont deconnectes (voir infrastructure/chat).
	h.chatHub.CloseStream(streamID)

	h.metrics.ActiveStreams.Dec()
	respondJSON(w, http.StatusOK, map[string]string{"status": "stopped"})
}

func (h *StreamHandler) GetListeners(w http.ResponseWriter, r *http.Request) {
	streamID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid stream id")
		return
	}

	listeners := h.hub.Listeners(streamID)
	if listeners == nil {
		listeners = []streaming.ListenerInfo{}
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"listeners": listeners,
		"count":     len(listeners),
	})
}

func toStreamResponse(s *domain.Stream) dto.StreamResponse {
	return dto.StreamResponse{
		ID:            s.ID.String(),
		Title:         s.Title,
		Description:   s.Description,
		OwnerID:       s.OwnerID.String(),
		Status:        string(s.Status),
		ListenerCount: s.ListenerCount,
		Format:        s.Format,
		CreatedAt:     s.CreatedAt,
		UpdatedAt:     s.UpdatedAt,
	}
}
