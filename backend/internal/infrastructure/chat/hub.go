// Package chat gere un salon de discussion ephemere par flux en direct.
// Meme pattern de fan-out (goroutines + channels) que le hub audio de
// streaming, avec en plus un petit historique en memoire par salon.
// Le transport (WebSocket) vit dans la couche HTTP, pas ici.
package chat

import (
	"encoding/json"
	"sync"

	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/streampulse/backend/internal/infrastructure/streaming"
)

// room est l'etat d'un salon : ses participants et les derniers messages.
type room struct {
	clients map[uuid.UUID]*streaming.Client
	history []Message
}

// Hub route les messages de chat vers les participants d'un meme flux.
// Il reutilise streaming.Client : un participant est exactement la meme
// chose qu'un auditeur (un channel de sortie + un signal de fermeture).
type Hub struct {
	mu     sync.RWMutex
	rooms  map[uuid.UUID]*room
	logger zerolog.Logger
}

func NewHub(logger zerolog.Logger) *Hub {
	return &Hub{
		rooms:  make(map[uuid.UUID]*room),
		logger: logger.With().Str("component", "chat_hub").Logger(),
	}
}

// Join ajoute le participant au salon du flux et lui met en file
// l'historique du salon. Les deux se font sous le meme verrou : un message
// publie apres le Join arrive forcement apres l'historique, jamais avant.
func (h *Hub) Join(streamID uuid.UUID, client *streaming.Client) {
	h.mu.Lock()
	rm, ok := h.rooms[streamID]
	if !ok {
		rm = &room{clients: make(map[uuid.UUID]*streaming.Client)}
		h.rooms[streamID] = rm
	}
	for _, msg := range rm.history {
		if data, err := json.Marshal(msg); err == nil {
			client.Send(data)
		}
	}
	rm.clients[client.ID] = client
	count := len(rm.clients)
	h.mu.Unlock()

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Str("client_id", client.ID.String()).
		Str("username", client.Username).
		Int("participants", count).
		Msg("chat participant joined")
}

// Leave retire le participant du salon ; le dernier parti emporte le salon
// (et son historique) avec lui.
func (h *Hub) Leave(streamID uuid.UUID, client *streaming.Client) {
	h.mu.Lock()
	if rm, ok := h.rooms[streamID]; ok {
		if _, exists := rm.clients[client.ID]; exists {
			client.Close()
			delete(rm.clients, client.ID)

			h.logger.Info().
				Str("stream_id", streamID.String()).
				Str("client_id", client.ID.String()).
				Str("username", client.Username).
				Int("participants", len(rm.clients)).
				Msg("chat participant left")

			if len(rm.clients) == 0 {
				delete(h.rooms, streamID)
			}
		}
	}
	h.mu.Unlock()
}

// Publish diffuse un message a tous les participants du salon. Seuls les
// vrais messages (TypeMessage) entrent dans l'historique ; les evenements
// de presence sont ephemeres.
func (h *Hub) Publish(streamID uuid.UUID, msg Message) {
	data, err := json.Marshal(msg)
	if err != nil {
		h.logger.Error().Err(err).Msg("cannot marshal chat message")
		return
	}

	h.mu.Lock()
	rm, ok := h.rooms[streamID]
	if !ok {
		h.mu.Unlock()
		return
	}
	if msg.Type == TypeMessage {
		rm.history = append(rm.history, msg)
		if len(rm.history) > historyLimit {
			rm.history = rm.history[len(rm.history)-historyLimit:]
		}
	}
	clients := make([]*streaming.Client, 0, len(rm.clients))
	for _, c := range rm.clients {
		clients = append(clients, c)
	}
	h.mu.Unlock()

	// Envoi non bloquant hors verrou, comme streaming.Hub.Broadcast : un
	// participant lent perd des messages, il ne bloque pas les autres.
	for _, client := range clients {
		if !client.Send(data) {
			h.Leave(streamID, client)
		}
	}
}

// CloseStream ferme le salon d'un flux : tous les participants sont
// deconnectes et l'historique est oublie. Appele quand le live s'arrete.
func (h *Hub) CloseStream(streamID uuid.UUID) {
	h.mu.Lock()
	rm, ok := h.rooms[streamID]
	if !ok {
		h.mu.Unlock()
		return
	}
	clients := make([]*streaming.Client, 0, len(rm.clients))
	for _, c := range rm.clients {
		clients = append(clients, c)
	}
	delete(h.rooms, streamID)
	h.mu.Unlock()

	for _, client := range clients {
		client.Close()
	}

	h.logger.Info().
		Str("stream_id", streamID.String()).
		Int("participants_closed", len(clients)).
		Msg("chat room closed")
}

// Participants retourne le nombre de personnes dans le salon d'un flux.
func (h *Hub) Participants(streamID uuid.UUID) int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if rm, ok := h.rooms[streamID]; ok {
		return len(rm.clients)
	}
	return 0
}

// ActiveRooms retourne le nombre de salons ouverts (pour les tests et les
// verifications de non-fuite).
func (h *Hub) ActiveRooms() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.rooms)
}
