package streaming

import (
	"sync"

	"github.com/google/uuid"
	"github.com/rs/zerolog"
)

type ListenerInfo struct {
	ClientID uuid.UUID `json:"client_id"`
	UserID   uuid.UUID `json:"user_id"`
	Username string    `json:"username"`
}

type Hub struct {
	mu      sync.RWMutex
	streams map[uuid.UUID]map[uuid.UUID]*Client
	logger  zerolog.Logger

	// Callback invoked when listener count changes for a stream
	OnListenerChange func(streamID uuid.UUID, count int)
}

func NewHub(logger zerolog.Logger) *Hub {
	return &Hub{
		streams: make(map[uuid.UUID]map[uuid.UUID]*Client),
		logger:  logger.With().Str("component", "streaming_hub").Logger(),
	}
}

func (h *Hub) Register(streamID uuid.UUID, client *Client) {
	h.mu.Lock()
	if _, ok := h.streams[streamID]; !ok {
		h.streams[streamID] = make(map[uuid.UUID]*Client)
	}
	h.streams[streamID][client.ID] = client
	count := len(h.streams[streamID])
	h.mu.Unlock()

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Str("client_id", client.ID.String()).
		Str("username", client.Username).
		Int("listener_count", count).
		Msg("client registered")

	if h.OnListenerChange != nil {
		h.OnListenerChange(streamID, count)
	}
}

func (h *Hub) Unregister(streamID uuid.UUID, client *Client) {
	h.mu.Lock()
	var count int
	if clients, ok := h.streams[streamID]; ok {
		if _, exists := clients[client.ID]; exists {
			client.Close()
			delete(clients, client.ID)
			count = len(clients)

			h.logger.Info().
				Str("stream_id", streamID.String()).
				Str("client_id", client.ID.String()).
				Str("username", client.Username).
				Int("listener_count", count).
				Msg("client unregistered")

			if count == 0 {
				delete(h.streams, streamID)
			}
		}
	}
	h.mu.Unlock()

	if h.OnListenerChange != nil {
		h.OnListenerChange(streamID, count)
	}
}

func (h *Hub) Broadcast(streamID uuid.UUID, data []byte) {
	h.mu.RLock()
	clients, ok := h.streams[streamID]
	if !ok {
		h.mu.RUnlock()
		return
	}

	clientList := make([]*Client, 0, len(clients))
	for _, c := range clients {
		clientList = append(clientList, c)
	}
	h.mu.RUnlock()

	var disconnected []*Client
	for _, client := range clientList {
		if !client.Send(data) {
			disconnected = append(disconnected, client)
		}
	}

	for _, client := range disconnected {
		h.Unregister(streamID, client)
	}
}

func (h *Hub) CloseStream(streamID uuid.UUID) {
	h.mu.Lock()
	clients, ok := h.streams[streamID]
	if !ok {
		h.mu.Unlock()
		return
	}

	clientList := make([]*Client, 0, len(clients))
	for _, c := range clients {
		clientList = append(clientList, c)
	}
	delete(h.streams, streamID)
	h.mu.Unlock()

	for _, client := range clientList {
		client.Close()
	}

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Int("clients_closed", len(clientList)).
		Msg("stream closed")

	if h.OnListenerChange != nil {
		h.OnListenerChange(streamID, 0)
	}
}

func (h *Hub) ListenerCount(streamID uuid.UUID) int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if clients, ok := h.streams[streamID]; ok {
		return len(clients)
	}
	return 0
}

func (h *Hub) Listeners(streamID uuid.UUID) []ListenerInfo {
	h.mu.RLock()
	defer h.mu.RUnlock()

	clients, ok := h.streams[streamID]
	if !ok {
		return nil
	}

	listeners := make([]ListenerInfo, 0, len(clients))
	for _, c := range clients {
		listeners = append(listeners, ListenerInfo{
			ClientID: c.ID,
			UserID:   c.UserID,
			Username: c.Username,
		})
	}
	return listeners
}

func (h *Hub) ActiveStreams() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.streams)
}

func (h *Hub) TotalListeners() int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	total := 0
	for _, clients := range h.streams {
		total += len(clients)
	}
	return total
}
