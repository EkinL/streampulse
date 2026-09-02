package http

import (
	"context"
	"encoding/json"
	nethttp "net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/chat"
	"github.com/streampulse/backend/testutil"
)

// Tests de bout en bout du chat de live : de vrais clients WebSocket a
// travers le routeur complet (middleware d'auth WS, upgrade, hub de chat),
// sur un serveur httptest. Seule la base est un mock en memoire.

// chatURL construit l'URL ws:// du salon d'un flux sur le serveur de test.
func chatURL(srv *httptest.Server, streamID uuid.UUID) string {
	return "ws" + strings.TrimPrefix(srv.URL, "http") + "/streams/" + streamID.String() + "/chat/ws"
}

// dialChat ouvre une connexion au salon, token porte par le header Bearer.
func dialChat(t *testing.T, srv *httptest.Server, streamID uuid.UUID, token string) *websocket.Conn {
	t.Helper()
	header := nethttp.Header{"Authorization": {"Bearer " + token}}
	conn, resp, err := websocket.DefaultDialer.Dial(chatURL(srv, streamID), header)
	if err != nil {
		status := 0
		if resp != nil {
			status = resp.StatusCode
		}
		t.Fatalf("dial chat: %v (status %d)", err, status)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return conn
}

// readChatMessage lit la prochaine trame et la decode, avec un garde-fou de
// temps pour qu'un test casse ne bloque pas la suite.
func readChatMessage(t *testing.T, conn *websocket.Conn) chat.Message {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	_, raw, err := conn.ReadMessage()
	if err != nil {
		t.Fatalf("read chat message: %v", err)
	}
	var m chat.Message
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("invalid chat frame %q: %v", raw, err)
	}
	return m
}

// liveChatStream seede un flux en direct dans le repo mocke partage.
func liveChatStream(t *testing.T, owner *domain.User) *domain.Stream {
	t.Helper()
	stream := testutil.NewTestStream(owner.ID)
	stream.Status = domain.StreamStatusLive
	if err := testRouterStreams.Create(context.Background(), stream); err != nil {
		t.Fatalf("seed stream: %v", err)
	}
	return stream
}

func TestChatFanOutBetweenParticipants(t *testing.T) {
	router, jwtManager := testRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	owner := testutil.NewTestUser(domain.RoleBroadcaster)
	stream := liveChatStream(t, owner)

	alice := testutil.NewTestUser(domain.RoleUser)
	bob := testutil.NewTestUser(domain.RoleUser)

	connAlice := dialChat(t, srv, stream.ID, testTokenFor(t, jwtManager, alice))
	if m := readChatMessage(t, connAlice); m.Type != chat.TypeUserJoined || m.Username != alice.Username {
		t.Fatalf("first frame = %+v, want alice's user_joined", m)
	}

	// Bob entre par le parametre `?token=`, comme un navigateur.
	urlWithToken := chatURL(srv, stream.ID) + "?token=" + testTokenFor(t, jwtManager, bob)
	connBob, _, err := websocket.DefaultDialer.Dial(urlWithToken, nil)
	if err != nil {
		t.Fatalf("dial with query token: %v", err)
	}
	defer func() { _ = connBob.Close() }()

	// Les deux voient l'arrivee de bob.
	for name, conn := range map[string]*websocket.Conn{"alice": connAlice, "bob": connBob} {
		if m := readChatMessage(t, conn); m.Type != chat.TypeUserJoined || m.Username != bob.Username {
			t.Fatalf("%s: got %+v, want bob's user_joined", name, m)
		}
	}

	// Un message trop long ou vide est ignore ; le suivant passe.
	tooLong := strings.Repeat("a", chat.MaxMessageRunes+1)
	for _, text := range []string{tooLong, "   ", "hello bob"} {
		if err := connAlice.WriteJSON(map[string]string{"text": text}); err != nil {
			t.Fatalf("write message: %v", err)
		}
	}

	for name, conn := range map[string]*websocket.Conn{"alice": connAlice, "bob": connBob} {
		m := readChatMessage(t, conn)
		if m.Type != chat.TypeMessage || m.Text != "hello bob" || m.Username != alice.Username {
			t.Fatalf("%s: got %+v, want alice's 'hello bob'", name, m)
		}
		if m.UserID != alice.ID {
			t.Fatalf("%s: message attributed to %s, want %s (identity must come from the token)", name, m.UserID, alice.ID)
		}
	}

	// Un retardataire recoit l'historique (le message, pas les presences).
	carol := testutil.NewTestUser(domain.RoleUser)
	connCarol := dialChat(t, srv, stream.ID, testTokenFor(t, jwtManager, carol))
	if m := readChatMessage(t, connCarol); m.Type != chat.TypeMessage || m.Text != "hello bob" {
		t.Fatalf("late joiner first frame = %+v, want replayed 'hello bob'", m)
	}
	if m := readChatMessage(t, connCarol); m.Type != chat.TypeUserJoined || m.Username != carol.Username {
		t.Fatalf("late joiner second frame = %+v, want carol's user_joined", m)
	}

	// Le depart de bob est annonce aux autres.
	_ = connBob.Close()
	// alice a aussi le user_joined de carol en file avant le user_left.
	if m := readChatMessage(t, connAlice); m.Type != chat.TypeUserJoined || m.Username != carol.Username {
		t.Fatalf("alice: got %+v, want carol's user_joined", m)
	}
	if m := readChatMessage(t, connAlice); m.Type != chat.TypeUserLeft || m.Username != bob.Username {
		t.Fatalf("alice: got %+v, want bob's user_left", m)
	}

	waitFor(t, 3*time.Second, func() bool {
		return testRouterChatHub.Participants(stream.ID) == 2
	}, "bob's departure not reflected in the hub")
}

func TestChatStopStreamClosesRoom(t *testing.T) {
	router, jwtManager := testRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	owner := testutil.NewTestUser(domain.RoleBroadcaster)
	stream := liveChatStream(t, owner)

	listener := testutil.NewTestUser(domain.RoleUser)
	conn := dialChat(t, srv, stream.ID, testTokenFor(t, jwtManager, listener))
	if m := readChatMessage(t, conn); m.Type != chat.TypeUserJoined {
		t.Fatalf("got %+v, want user_joined", m)
	}

	// Le diffuseur arrete son live via l'API : le salon doit fermer.
	req, err := nethttp.NewRequest(nethttp.MethodPost, srv.URL+"/streams/"+stream.ID.String()+"/stop", nil)
	if err != nil {
		t.Fatalf("build stop request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+testTokenFor(t, jwtManager, owner))
	resp, err := srv.Client().Do(req)
	if err != nil {
		t.Fatalf("stop stream: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != nethttp.StatusOK {
		t.Fatalf("stop stream: status %d, want 200", resp.StatusCode)
	}

	// Le client recoit une trame de fermeture "going away", pas une coupure.
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	_, _, err = conn.ReadMessage()
	closeErr, ok := err.(*websocket.CloseError)
	if !ok || closeErr.Code != websocket.CloseGoingAway {
		t.Fatalf("read after stop: err = %v, want close frame %d (going away)", err, websocket.CloseGoingAway)
	}

	waitFor(t, 3*time.Second, func() bool {
		return testRouterChatHub.ActiveRooms() == 0
	}, "chat room still open after the stream stopped")
}

func TestChatRejectsWithoutToken(t *testing.T) {
	router, _ := testRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	_, resp, err := websocket.DefaultDialer.Dial(chatURL(srv, uuid.New()), nil)
	if err == nil {
		t.Fatal("dial without token succeeded, want 401")
	}
	if resp == nil || resp.StatusCode != nethttp.StatusUnauthorized {
		t.Fatalf("got %v, want status 401", resp)
	}
}

func TestChatRejectsWhenStreamNotLive(t *testing.T) {
	router, jwtManager := testRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	owner := testutil.NewTestUser(domain.RoleBroadcaster)
	stream := testutil.NewTestStream(owner.ID) // status par defaut : pas live
	if err := testRouterStreams.Create(context.Background(), stream); err != nil {
		t.Fatalf("seed stream: %v", err)
	}

	user := testutil.NewTestUser(domain.RoleUser)
	header := nethttp.Header{"Authorization": {"Bearer " + testTokenFor(t, jwtManager, user)}}
	_, resp, err := websocket.DefaultDialer.Dial(chatURL(srv, stream.ID), header)
	if err == nil {
		t.Fatal("dial on a non-live stream succeeded, want 400")
	}
	if resp == nil || resp.StatusCode != nethttp.StatusBadRequest {
		t.Fatalf("got %v, want status 400", resp)
	}
}
