package chat

import (
	"time"

	"github.com/google/uuid"
)

// Types d'evenements envoyes sur le WebSocket. Chaque trame est un Message
// serialise en JSON ; le champ Type dit au client comment l'afficher.
const (
	TypeMessage    = "message"
	TypeUserJoined = "user_joined"
	TypeUserLeft   = "user_left"
)

// Contraintes du chat. Des constantes de code, comme clientBufferSize dans
// streaming : ce sont des regles du protocole, pas de la configuration de
// deploiement.
const (
	// MaxMessageRunes borne la longueur d'un message utilisateur.
	MaxMessageRunes = 500
	// historyLimit : nombre de messages gardes en memoire par salon, pour
	// qu'un auditeur qui rejoint le live voie la conversation en cours.
	// Rien n'est persiste en base : le salon meurt avec le live.
	historyLimit = 50
)

type Message struct {
	Type     string    `json:"type"`
	ID       uuid.UUID `json:"id"`
	StreamID uuid.UUID `json:"stream_id"`
	UserID   uuid.UUID `json:"user_id"`
	Username string    `json:"username"`
	Text     string    `json:"text,omitempty"`
	SentAt   time.Time `json:"sent_at"`
}

// NewUserMessage construit un message de chat d'un participant.
func NewUserMessage(streamID, userID uuid.UUID, username, text string) Message {
	return Message{
		Type:     TypeMessage,
		ID:       uuid.New(),
		StreamID: streamID,
		UserID:   userID,
		Username: username,
		Text:     text,
		SentAt:   time.Now().UTC(),
	}
}

// NewPresenceMessage construit un evenement d'arrivee ou de depart.
func NewPresenceMessage(msgType string, streamID, userID uuid.UUID, username string) Message {
	return Message{
		Type:     msgType,
		ID:       uuid.New(),
		StreamID: streamID,
		UserID:   userID,
		Username: username,
		SentAt:   time.Now().UTC(),
	}
}
