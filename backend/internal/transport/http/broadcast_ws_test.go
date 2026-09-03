package http

import (
	"context"
	"io"
	nethttp "net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/testutil"
)

// Bout en bout de l'ingest WebSocket a travers le routeur complet (auth WS
// par `?token=` comme la console web, RBAC, upgrade, hub de streaming) : ce
// que le diffuseur envoie ressort chez un auditeur du flux audio brut.

func broadcastURL(srv *httptest.Server, streamID uuid.UUID, token string) string {
	return "ws" + strings.TrimPrefix(srv.URL, "http") + "/streams/" + streamID.String() + "/broadcast/ws?token=" + token
}

func TestBroadcastWebSocketReachesAudioListeners(t *testing.T) {
	router, jwtManager := testRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	owner := testutil.NewTestUser(domain.RoleBroadcaster)
	stream := liveChatStream(t, owner)
	listener := testutil.NewTestUser(domain.RoleUser)

	// Un auditeur sur le flux brut, comme le lecteur mobile.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	req, err := nethttp.NewRequestWithContext(ctx, nethttp.MethodGet, srv.URL+"/streams/"+stream.ID.String()+"/audio", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+testTokenFor(t, jwtManager, listener))
	resp, err := nethttp.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != nethttp.StatusOK {
		t.Fatalf("audio: statut %d, attendu 200", resp.StatusCode)
	}
	deadline := time.Now().Add(5 * time.Second)
	for testRouterHub.ListenerCount(stream.ID) == 0 {
		if time.Now().After(deadline) {
			t.Fatal("l'auditeur ne s'est pas enregistre")
		}
		time.Sleep(10 * time.Millisecond)
	}

	// Un simple auditeur ne peut pas diffuser : refuse a la poignee de main.
	if conn, resp, err := websocket.DefaultDialer.Dial(broadcastURL(srv, stream.ID, testTokenFor(t, jwtManager, listener)), nil); err == nil {
		_ = conn.Close()
		t.Fatal("un auditeur a pu ouvrir l'ingest")
	} else if resp == nil || resp.StatusCode != nethttp.StatusForbidden {
		t.Fatalf("ingest par un auditeur: reponse %+v, attendu 403", resp)
	}

	// Le proprietaire entre par `?token=`, comme le navigateur de la console.
	conn, _, err := websocket.DefaultDialer.Dial(broadcastURL(srv, stream.ID, testTokenFor(t, jwtManager, owner)), nil)
	if err != nil {
		t.Fatalf("dial broadcast: %v", err)
	}
	defer func() { _ = conn.Close() }()

	payload := []byte("trame-pcm")
	if err := conn.WriteMessage(websocket.BinaryMessage, payload); err != nil {
		t.Fatalf("write frame: %v", err)
	}

	buf := make([]byte, len(payload))
	if _, err := io.ReadFull(resp.Body, buf); err != nil {
		t.Fatalf("lecture du flux audio: %v", err)
	}
	if string(buf) != string(payload) {
		t.Fatalf("auditeur a recu %q, attendu %q", buf, payload)
	}
}
