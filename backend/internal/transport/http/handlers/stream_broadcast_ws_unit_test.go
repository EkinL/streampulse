package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	"github.com/streampulse/backend/internal/transport/http/middleware"
	"github.com/streampulse/backend/testutil"
)

// broadcastWSServer sert BroadcastWS avec les claims donnes, comme le ferait
// le middleware d'auth WebSocket. Un vrai serveur : l'upgrade a besoin d'une
// connexion a hijacker, ce qu'un ResponseRecorder ne sait pas faire.
func broadcastWSServer(t *testing.T, h *streamHarness, claims *auth.Claims) *httptest.Server {
	t.Helper()
	router := chi.NewRouter()
	router.Get("/streams/{id}/broadcast/ws", func(w http.ResponseWriter, r *http.Request) {
		r = r.WithContext(context.WithValue(r.Context(), middleware.UserContextKey, claims))
		h.handler.BroadcastWS(w, r)
	})
	srv := httptest.NewServer(router)
	t.Cleanup(srv.Close)
	return srv
}

func broadcastWSURL(srv *httptest.Server, streamID uuid.UUID) string {
	return "ws" + strings.TrimPrefix(srv.URL, "http") + "/streams/" + streamID.String() + "/broadcast/ws"
}

// Chaque trame binaire est un chunk audio, remis dans l'ordre aux auditeurs
// du Hub ; une trame texte n'est pas de l'audio et est ignoree.
func TestStreamHandlerBroadcastWSFansOutFrames(t *testing.T) {
	h := newStreamHarness()
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)
	srv := broadcastWSServer(t, h, unitClaims(ownerID, domain.RoleBroadcaster))

	listener := streaming.NewClient(uuid.New(), "alice")
	h.hub.Register(stream.ID, listener)
	defer h.hub.Unregister(stream.ID, listener)

	conn, _, err := websocket.DefaultDialer.Dial(broadcastWSURL(srv, stream.ID), nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if err := conn.WriteMessage(websocket.TextMessage, []byte("pas de l'audio")); err != nil {
		t.Fatalf("write text: %v", err)
	}
	chunks := []string{"chunk-1", "chunk-2"}
	for _, chunk := range chunks {
		if err := conn.WriteMessage(websocket.BinaryMessage, []byte(chunk)); err != nil {
			t.Fatalf("write %q: %v", chunk, err)
		}
	}

	for _, want := range chunks {
		select {
		case got := <-listener.Ch:
			if string(got) != want {
				t.Fatalf("auditeur a recu %q, attendu %q", got, want)
			}
		case <-time.After(3 * time.Second):
			t.Fatalf("chunk %q jamais recu par l'auditeur", want)
		}
	}
	select {
	case got := <-listener.Ch:
		t.Fatalf("trame inattendue recue par l'auditeur: %q", got)
	default:
	}
}

// Les refus se font a la poignee de main, avec le meme code que le POST :
// le client sait pourquoi avant d'avoir ouvert le micro.
func TestStreamHandlerBroadcastWSRefusals(t *testing.T) {
	h := newStreamHarness()
	ownerID := uuid.New()
	live := h.liveStream(t, ownerID)
	idle := testutil.NewTestStream(ownerID)
	if err := h.repo.MockStreamRepo.Create(context.Background(), idle); err != nil {
		t.Fatalf("create idle stream: %v", err)
	}

	cases := []struct {
		name     string
		claims   *auth.Claims
		streamID uuid.UUID
		status   int
	}{
		{"non proprietaire", unitClaims(uuid.New(), domain.RoleBroadcaster), live.ID, http.StatusForbidden},
		{"flux pas en direct", unitClaims(ownerID, domain.RoleBroadcaster), idle.ID, http.StatusBadRequest},
		{"flux inconnu", unitClaims(ownerID, domain.RoleBroadcaster), uuid.New(), http.StatusNotFound},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			srv := broadcastWSServer(t, h, tc.claims)
			conn, resp, err := websocket.DefaultDialer.Dial(broadcastWSURL(srv, tc.streamID), nil)
			if err == nil {
				_ = conn.Close()
				t.Fatal("la poignee de main aurait du etre refusee")
			}
			if resp == nil || resp.StatusCode != tc.status {
				t.Fatalf("reponse %+v, attendu statut %d", resp, tc.status)
			}
		})
	}
}

// Connexion fermee sans remplacement dans le delai de grace : le direct est
// arrete comme pour le POST, et les auditeurs deconnectes.
func TestStreamHandlerBroadcastWSAutoStopsWhenBroadcasterGone(t *testing.T) {
	h := newStreamHarnessWithGrace(30 * time.Millisecond)
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)
	srv := broadcastWSServer(t, h, unitClaims(ownerID, domain.RoleBroadcaster))

	listener := streaming.NewClient(uuid.New(), "alice")
	h.hub.Register(stream.ID, listener)

	conn, _, err := websocket.DefaultDialer.Dial(broadcastWSURL(srv, stream.ID), nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	if err := conn.WriteMessage(websocket.BinaryMessage, []byte("x")); err != nil {
		t.Fatalf("write: %v", err)
	}
	_ = conn.WriteMessage(websocket.CloseMessage,
		websocket.FormatCloseMessage(websocket.CloseNormalClosure, "antenne coupee"))
	_ = conn.Close()

	waitUntil(t, 5*time.Second, func() bool {
		s, err := h.repo.FindByID(context.Background(), stream.ID)
		return err == nil && s.Status == domain.StreamStatusEnded
	}, "le flux n'a pas ete arrete automatiquement")
	select {
	case <-listener.Done():
	case <-time.After(time.Second):
		t.Fatal("l'auditeur n'a pas ete deconnecte")
	}
}
