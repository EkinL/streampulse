package handlers

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
)

// Timeouts serveur volontairement courts : le handler doit tenir plus
// longtemps que ca pour prouver que les deadlines ont bien ete levees.
const testServerTimeout = 150 * time.Millisecond

func newTimeoutServer(t *testing.T, h http.HandlerFunc) *httptest.Server {
	t.Helper()
	srv := httptest.NewUnstartedServer(h)
	srv.Config.ReadTimeout = testServerTimeout
	srv.Config.WriteTimeout = testServerTimeout
	srv.Start()
	t.Cleanup(srv.Close)
	return srv
}

func rawWrite(t *testing.T, conn net.Conn, s string) {
	t.Helper()
	if _, err := io.WriteString(conn, s); err != nil {
		t.Fatalf("ecriture sur la connexion: %v", err)
	}
}

// Meme forme qu'un handler SSE : un premier flush, puis une ecriture bien
// apres le WriteTimeout du serveur.
func slowStreamHandler(keepOpen bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if keepOpen {
			keepConnectionOpen(w, zerolog.Nop())
		}
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = fmt.Fprint(w, "data: hello\n\n")
		w.(http.Flusher).Flush()

		time.Sleep(3 * testServerTimeout)

		_, _ = fmt.Fprint(w, "data: still here\n\n")
		w.(http.Flusher).Flush()
	}
}

func TestKeepConnectionOpenSurvivesWriteTimeout(t *testing.T) {
	srv := newTimeoutServer(t, slowStreamHandler(true))

	resp, err := http.Get(srv.URL)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("lecture du corps: %v", err)
	}
	if !strings.Contains(string(body), "still here") {
		t.Fatalf("le second evenement n'est pas arrive, la deadline d'ecriture n'a pas ete levee. corps: %q", body)
	}
}

// Cas temoin : sans keepConnectionOpen le serveur coupe la connexion a
// WriteTimeout et le second evenement est perdu. Si ce test se met a passer
// c'est que le serveur de test n'a plus de timeout et que le test du dessus
// ne prouve plus rien.
func TestWriteTimeoutCutsStreamWithoutKeepConnectionOpen(t *testing.T) {
	srv := newTimeoutServer(t, slowStreamHandler(false))

	resp, err := http.Get(srv.URL)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	body, _ := io.ReadAll(resp.Body)
	if strings.Contains(string(body), "still here") {
		t.Fatalf("le second evenement est passe alors que WriteTimeout aurait du couper la connexion")
	}
}

// Meme forme que Broadcast : le client envoie le corps petit a petit, bien
// au dela du ReadTimeout du serveur.
func TestKeepConnectionOpenSurvivesReadTimeout(t *testing.T) {
	received := make(chan string, 1)
	srv := newTimeoutServer(t, func(w http.ResponseWriter, r *http.Request) {
		keepConnectionOpen(w, zerolog.Nop())
		body, err := io.ReadAll(r.Body)
		if err != nil {
			received <- "err: " + err.Error()
			return
		}
		received <- string(body)
	})

	conn, err := net.Dial("tcp", strings.TrimPrefix(srv.URL, "http://"))
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer func() { _ = conn.Close() }()

	const payload = "chunk1chunk2"
	rawWrite(t, conn, fmt.Sprintf("POST /streams/x/broadcast HTTP/1.1\r\nHost: test\r\nContent-Length: %d\r\n\r\n", len(payload)))
	rawWrite(t, conn, "chunk1")
	time.Sleep(3 * testServerTimeout)
	rawWrite(t, conn, "chunk2")

	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatalf("le serveur a coupe la connexion au lieu d'attendre le corps: %v", err)
	}
	_ = resp.Body.Close()

	select {
	case got := <-received:
		if got != payload {
			t.Fatalf("corps recu %q, attendu %q", got, payload)
		}
	case <-time.After(time.Second):
		t.Fatal("le handler n'a jamais fini de lire le corps")
	}
}

func TestExtendDeadlinesCoversSlowUpload(t *testing.T) {
	received := make(chan error, 1)
	srv := newTimeoutServer(t, func(w http.ResponseWriter, r *http.Request) {
		if err := extendDeadlines(w, time.Second); err != nil {
			received <- err
			return
		}
		_, err := io.ReadAll(r.Body)
		received <- err
	})

	conn, err := net.Dial("tcp", strings.TrimPrefix(srv.URL, "http://"))
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer func() { _ = conn.Close() }()

	rawWrite(t, conn, "POST /music HTTP/1.1\r\nHost: test\r\nContent-Length: 4\r\n\r\n")
	time.Sleep(3 * testServerTimeout)
	rawWrite(t, conn, "file")

	if _, err := http.ReadResponse(bufio.NewReader(conn), nil); err != nil {
		t.Fatalf("connexion coupee malgre la deadline etendue: %v", err)
	}
	if err := <-received; err != nil {
		t.Fatalf("lecture du corps: %v", err)
	}
}

// Meme forme que Broadcast a l'arret du serveur : le diffuseur ne dit plus
// rien, on annule le contexte de base et le handler doit sortir de son Read.
func TestUnblockReadOnCancelReleasesBlockedBody(t *testing.T) {
	baseCtx, cancelBase := context.WithCancel(context.Background())
	defer cancelBase()

	done := make(chan error, 1)
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		keepConnectionOpen(w, zerolog.Nop())
		defer unblockReadOnCancel(r.Context(), w)()
		_, err := io.ReadAll(r.Body)
		done <- err
	}))
	srv.Config.BaseContext = func(net.Listener) context.Context { return baseCtx }
	srv.Start()
	t.Cleanup(srv.Close)

	conn, err := net.Dial("tcp", strings.TrimPrefix(srv.URL, "http://"))
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer func() { _ = conn.Close() }()

	// Corps annonce mais jamais envoye : le handler bloque dans Read.
	rawWrite(t, conn, "POST /streams/x/broadcast HTTP/1.1\r\nHost: test\r\nContent-Length: 4096\r\n\r\n")
	time.Sleep(testServerTimeout)

	select {
	case err := <-done:
		t.Fatalf("le handler est sorti avant l'annulation: %v", err)
	default:
	}

	cancelBase()

	select {
	case err := <-done:
		if err == nil {
			t.Fatal("Read a rendu nil alors que la connexion a ete abandonnee")
		}
	case <-time.After(time.Second):
		t.Fatal("le handler est toujours bloque dans Read apres annulation du contexte")
	}
}

// Les helpers ne doivent pas casser les tests unitaires qui passent par un
// ResponseRecorder, lequel ne supporte pas les deadlines.
func TestDeadlineHelpersTolerateRecorder(t *testing.T) {
	rec := httptest.NewRecorder()
	if err := clearDeadlines(rec); err != nil {
		t.Fatalf("clearDeadlines sur un recorder: %v", err)
	}
	if err := extendDeadlines(rec, time.Second); err != nil {
		t.Fatalf("extendDeadlines sur un recorder: %v", err)
	}
}
