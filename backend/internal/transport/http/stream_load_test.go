package http

import (
	"bufio"
	"context"
	"encoding/base64"
	"fmt"
	"io"
	nethttp "net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	promtestutil "github.com/prometheus/client_golang/prometheus/testutil"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/testutil"
)

// Test de charge de bout en bout : N vrais clients HTTP ecoutent un flux en
// SSE pendant qu'un diffuseur pousse de l'audio en chunked POST. Tout passe
// par le routeur complet (JWT, RBAC, rate-limit, Hub) sur un serveur
// httptest, comme en production sauf la base (mock en memoire).
//
// Ce que le test prouve :
//   - N auditeurs simultanes recoivent chacun l'integralite du flux, dans
//     l'ordre, sans corruption ;
//   - a la deconnexion des auditeurs, le Hub et la gauge active_listeners
//     reviennent a zero (aucune goroutine de handler ni entree de Hub ne fuit).

const (
	loadChunkSize = 4096
	// 64 chunks de 4 KiB = 256 KiB par auditeur, en dessous du buffer client
	// du Hub (256 chunks) : un auditeur momentanement lent ne perd rien.
	loadChunks = 64
)

func testTokenFor(t *testing.T, m *auth.JWTManager, user *domain.User) string {
	t.Helper()
	pair, err := m.GenerateTokenPair(user)
	if err != nil {
		t.Fatalf("generate token pair: %v", err)
	}
	return pair.AccessToken
}

func waitFor(t *testing.T, timeout time.Duration, cond func() bool, msg string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timeout after %s: %s", timeout, msg)
}

// patternByte rend le flux verifiable : l'octet a la position i du flux vaut
// toujours i mod 251. Un chunk perdu, duplique ou reordonne casse la suite.
func patternByte(i int) byte { return byte(i % 251) }

// listenSSE se connecte a /streams/{id}/listen, signale la connexion, puis
// verifie chaque octet recu jusqu'a wantBytes. Il coupe ensuite la connexion
// (cancel) comme le ferait un client qui quitte l'app.
func listenSSE(ctx context.Context, client *nethttp.Client, url, token string, wantBytes int, connected *atomic.Int64) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	req, err := nethttp.NewRequestWithContext(ctx, nethttp.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != nethttp.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("status %d: %s", resp.StatusCode, body)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		return fmt.Errorf("content-type %q, want text/event-stream", ct)
	}

	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	received := 0
	skipNextData := false
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case line == "event: connected":
			skipNextData = true // la ligne data suivante est le JSON de bienvenue
			connected.Add(1)
		case strings.HasPrefix(line, "data: "):
			if skipNextData {
				skipNextData = false
				continue
			}
			chunk, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(line, "data: "))
			if err != nil {
				return fmt.Errorf("invalid base64 payload: %w", err)
			}
			for _, b := range chunk {
				if b != patternByte(received) {
					return fmt.Errorf("byte %d = %d, want %d (stream corrupted or reordered)", received, b, patternByte(received))
				}
				received++
			}
			if received == wantBytes {
				return nil // flux complet : on se deconnecte
			}
			if received > wantBytes {
				return fmt.Errorf("received %d bytes, want exactly %d", received, wantBytes)
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("after %d/%d bytes: %w", received, wantBytes, err)
	}
	return fmt.Errorf("server closed the stream after %d/%d bytes", received, wantBytes)
}

func TestStreamFanOutOverSSE(t *testing.T) {
	listeners := 500
	if testing.Short() {
		listeners = 50
	}

	router, jwtManager := testRouter(t)
	server := httptest.NewServer(router)
	defer server.Close()

	owner := testutil.NewTestUser(domain.RoleBroadcaster)
	stream := testutil.NewTestStream(owner.ID)
	stream.Status = domain.StreamStatusLive
	if err := testRouterStreams.Create(context.Background(), stream); err != nil {
		t.Fatalf("seed stream: %v", err)
	}

	listenerToken := testTokenFor(t, jwtManager, testutil.NewTestUser(domain.RoleUser))
	broadcasterToken := testTokenFor(t, jwtManager, owner)
	listenURL := fmt.Sprintf("%s/streams/%s/listen", server.URL, stream.ID)
	broadcastURL := fmt.Sprintf("%s/streams/%s/broadcast", server.URL, stream.ID)

	activeBefore := promtestutil.ToFloat64(testRouterMetrics.ActiveListeners)
	disconnectsBefore := promtestutil.ToFloat64(testRouterMetrics.StreamDisconnections)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	// --- N auditeurs se connectent ------------------------------------------
	wantBytes := loadChunks * loadChunkSize
	var connected atomic.Int64
	errs := make(chan error, listeners)
	var wg sync.WaitGroup
	for i := 0; i < listeners; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := listenSSE(ctx, server.Client(), listenURL, listenerToken, wantBytes, &connected); err != nil {
				errs <- err
			}
		}()
	}

	waitFor(t, 30*time.Second, func() bool {
		return connected.Load() == int64(listeners) && testRouterHub.ListenerCount(stream.ID) == listeners
	}, fmt.Sprintf("only %d/%d listeners connected (hub sees %d)", connected.Load(), listeners, testRouterHub.ListenerCount(stream.ID)))

	if got := promtestutil.ToFloat64(testRouterMetrics.ActiveListeners) - activeBefore; got != float64(listeners) {
		t.Fatalf("active_listeners gauge = %v, want %d", got, listeners)
	}

	// --- Le diffuseur pousse le flux ----------------------------------------
	start := time.Now()
	pr, pw := io.Pipe()
	broadcastDone := make(chan error, 1)
	go func() {
		req, err := nethttp.NewRequestWithContext(ctx, nethttp.MethodPost, broadcastURL, pr)
		if err != nil {
			broadcastDone <- err
			return
		}
		req.Header.Set("Authorization", "Bearer "+broadcasterToken)
		req.Header.Set("Content-Type", "application/octet-stream")
		resp, err := server.Client().Do(req)
		if err != nil {
			broadcastDone <- err
			return
		}
		resp.Body.Close()
		if resp.StatusCode != nethttp.StatusOK {
			broadcastDone <- fmt.Errorf("broadcast status %d", resp.StatusCode)
			return
		}
		broadcastDone <- nil
	}()

	chunk := make([]byte, loadChunkSize)
	for c := 0; c < loadChunks; c++ {
		for i := range chunk {
			chunk[i] = patternByte(c*loadChunkSize + i)
		}
		if _, err := pw.Write(chunk); err != nil {
			t.Fatalf("broadcaster write: %v", err)
		}
	}
	pw.Close()
	if err := <-broadcastDone; err != nil {
		t.Fatalf("broadcaster: %v", err)
	}

	// --- Chaque auditeur a tout recu ----------------------------------------
	wg.Wait()
	close(errs)
	failed := 0
	for err := range errs {
		failed++
		if failed <= 5 {
			t.Errorf("listener: %v", err)
		}
	}
	if failed > 0 {
		t.Fatalf("%d/%d listeners did not receive the complete stream", failed, listeners)
	}
	elapsed := time.Since(start)
	totalMiB := float64(wantBytes*listeners) / (1024 * 1024)
	t.Logf("%d SSE listeners x %d KiB = %.1f MiB delivered end-to-end in %s (%.0f MiB/s)",
		listeners, wantBytes/1024, totalMiB, elapsed, totalMiB/elapsed.Seconds())

	// --- Tout est nettoye a la deconnexion ----------------------------------
	waitFor(t, 30*time.Second, func() bool {
		return testRouterHub.ListenerCount(stream.ID) == 0 &&
			promtestutil.ToFloat64(testRouterMetrics.ActiveListeners) == activeBefore
	}, fmt.Sprintf("hub still has %d listeners, active_listeners gauge = %v (want %v)",
		testRouterHub.ListenerCount(stream.ID), promtestutil.ToFloat64(testRouterMetrics.ActiveListeners), activeBefore))

	if got := promtestutil.ToFloat64(testRouterMetrics.StreamDisconnections) - disconnectsBefore; got != float64(listeners) {
		t.Fatalf("stream_disconnections_total delta = %v, want %d", got, listeners)
	}
}
