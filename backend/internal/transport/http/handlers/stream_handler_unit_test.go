package handlers

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/chat"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	"github.com/streampulse/backend/internal/transport/http/middleware"
	"github.com/streampulse/backend/testutil"
)

type streamHarness struct {
	handler *StreamHandler
	repo    *stubStreamRepo
	hub     *streaming.Hub
}

// newStreamHarness pose un delai de grace d'une heure : l'arret automatique
// d'un direct sans diffuseur ne se declenche pas au milieu des autres tests.
func newStreamHarness() *streamHarness {
	return newStreamHarnessWithGrace(time.Hour)
}

func newStreamHarnessWithGrace(grace time.Duration) *streamHarness {
	repo := &stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo()}
	hub := streaming.NewHub(zerolog.Nop())
	svc := application.NewStreamService(repo, hub)
	return &streamHarness{
		handler: NewStreamHandler(svc, hub, chat.NewHub(zerolog.Nop()), zerolog.Nop(), testMetrics, grace),
		repo:    repo,
		hub:     hub,
	}
}

// liveStream cree un flux deja en direct appartenant a ownerID.
func (h *streamHarness) liveStream(t *testing.T, ownerID uuid.UUID) *domain.Stream {
	t.Helper()
	stream := testutil.NewTestStream(ownerID)
	stream.Status = domain.StreamStatusLive
	if err := h.repo.MockStreamRepo.Create(context.Background(), stream); err != nil {
		t.Fatalf("create stream: %v", err)
	}
	return stream
}

func TestStreamHandlerRequiresAuthentication(t *testing.T) {
	h := newStreamHarness()
	cases := map[string]http.HandlerFunc{
		"create":       h.handler.CreateStream,
		"update":       h.handler.UpdateStream,
		"listen":       h.handler.Listen,
		"audio":        h.handler.AudioStream,
		"start":        h.handler.StartStream,
		"broadcast":    h.handler.Broadcast,
		"broadcast_ws": h.handler.BroadcastWS,
		"stop":         h.handler.StopStream,
	}
	for name, fn := range cases {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, "/streams", strings.NewReader("{}"))
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusUnauthorized, "UNAUTHORIZED")
		})
	}
}

func TestStreamHandlerRejectsInvalidID(t *testing.T) {
	h := newStreamHarness()
	claims := unitClaims(uuid.New(), domain.RoleBroadcaster)
	cases := map[string]http.HandlerFunc{
		"update":       h.handler.UpdateStream,
		"get":          h.handler.GetStream,
		"listen":       h.handler.Listen,
		"audio":        h.handler.AudioStream,
		"start":        h.handler.StartStream,
		"broadcast":    h.handler.Broadcast,
		"broadcast_ws": h.handler.BroadcastWS,
		"stop":         h.handler.StopStream,
		"listeners":    h.handler.GetListeners,
	}
	for name, fn := range cases {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, "/streams/zzz", strings.NewReader("{}"))
			req = reqWithClaims(req, claims)
			req = reqWithParams(req, "id", "pas-un-uuid")
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
		})
	}
}

func TestStreamHandlerUpdateRejectsInvalidBody(t *testing.T) {
	h := newStreamHarness()
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPut, "/streams/"+stream.ID.String(), strings.NewReader("{pas du json"))
	req = reqWithClaims(req, unitClaims(ownerID, domain.RoleBroadcaster))
	req = reqWithParams(req, "id", stream.ID.String())
	h.handler.UpdateStream(rec, req)
	wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
}

// Une panne du depot ne doit jamais passer pour un not found : chaque route
// repond INTERNAL_ERROR.
func TestStreamHandlerRepoFailures(t *testing.T) {
	ownerID := uuid.New()
	claims := unitClaims(ownerID, domain.RoleBroadcaster)

	run := func(prepare func(*streamHarness) (*http.Request, http.HandlerFunc)) *httptest.ResponseRecorder {
		h := newStreamHarness()
		req, fn := prepare(h)
		rec := httptest.NewRecorder()
		fn(rec, req)
		return rec
	}

	t.Run("list", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			h.repo.listErr = errInfra
			return httptest.NewRequest(http.MethodGet, "/streams", nil), h.handler.ListStreams
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("create", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			h.repo.createErr = errInfra
			req := httptest.NewRequest(http.MethodPost, "/streams", strings.NewReader(`{"title":"t"}`))
			return reqWithClaims(req, claims), h.handler.CreateStream
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("get", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			h.repo.findErr = errInfra
			req := httptest.NewRequest(http.MethodGet, "/streams/x", nil)
			return reqWithParams(req, "id", uuid.New().String()), h.handler.GetStream
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("update", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			stream := h.liveStream(t, ownerID)
			h.repo.updateErr = errInfra
			req := httptest.NewRequest(http.MethodPut, "/streams/x", strings.NewReader(`{"title":"t"}`))
			req = reqWithClaims(req, claims)
			return reqWithParams(req, "id", stream.ID.String()), h.handler.UpdateStream
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("listen", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			h.repo.findErr = errInfra
			req := httptest.NewRequest(http.MethodGet, "/streams/x/listen", nil)
			req = reqWithClaims(req, claims)
			return reqWithParams(req, "id", uuid.New().String()), h.handler.Listen
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("audio", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			h.repo.findErr = errInfra
			req := httptest.NewRequest(http.MethodGet, "/streams/x/audio", nil)
			req = reqWithClaims(req, claims)
			return reqWithParams(req, "id", uuid.New().String()), h.handler.AudioStream
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("broadcast", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			h.repo.findErr = errInfra
			req := httptest.NewRequest(http.MethodPost, "/streams/x/broadcast", nil)
			req = reqWithClaims(req, claims)
			return reqWithParams(req, "id", uuid.New().String()), h.handler.Broadcast
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("start", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			stream := testutil.NewTestStream(ownerID)
			if err := h.repo.MockStreamRepo.Create(context.Background(), stream); err != nil {
				t.Fatalf("create: %v", err)
			}
			h.repo.statusErr = errInfra
			req := httptest.NewRequest(http.MethodPost, "/streams/x/start", nil)
			req = reqWithClaims(req, claims)
			return reqWithParams(req, "id", stream.ID.String()), h.handler.StartStream
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("stop", func(t *testing.T) {
		rec := run(func(h *streamHarness) (*http.Request, http.HandlerFunc) {
			stream := h.liveStream(t, ownerID)
			h.repo.statusErr = errInfra
			req := httptest.NewRequest(http.MethodPost, "/streams/x/stop", nil)
			req = reqWithClaims(req, claims)
			return reqWithParams(req, "id", stream.ID.String()), h.handler.StopStream
		})
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})
}

// Sans http.Flusher, pas de streaming possible : le handler doit le dire
// plutot que de bloquer.
func TestStreamHandlerRequiresFlusher(t *testing.T) {
	h := newStreamHarness()
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)
	claims := unitClaims(ownerID, domain.RoleUser)

	for name, fn := range map[string]http.HandlerFunc{
		"listen": h.handler.Listen,
		"audio":  h.handler.AudioStream,
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodGet, "/streams/x", nil)
			req = reqWithClaims(req, claims)
			req = reqWithParams(req, "id", stream.ID.String())
			fn(noFlushWriter{rec}, req)
			wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
		})
	}
}

// AudioStream de bout en bout : un vrai client HTTP recoit les octets bruts
// pousses dans le Hub, puis la coupure du client libere le handler.
func TestStreamHandlerAudioStreamDeliversChunks(t *testing.T) {
	h := newStreamHarness()
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)
	claims := unitClaims(uuid.New(), domain.RoleUser)

	router := chi.NewRouter()
	router.Get("/streams/{id}/audio", func(w http.ResponseWriter, r *http.Request) {
		r = r.WithContext(context.WithValue(r.Context(), middleware.UserContextKey, claims))
		h.handler.AudioStream(w, r)
	})
	srv := httptest.NewServer(router)
	defer srv.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL+"/streams/"+stream.ID.String()+"/audio", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("do: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("statut attendu 200, obtenu %d", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "application/octet-stream" {
		t.Fatalf("Content-Type attendu application/octet-stream, obtenu %q", ct)
	}

	waitUntil(t, 5*time.Second, func() bool { return h.hub.ListenerCount(stream.ID) == 1 }, "l'auditeur ne s'est pas enregistre")

	payload := []byte("audio-brut")
	h.hub.Broadcast(stream.ID, payload)

	buf := make([]byte, len(payload))
	if _, err := io.ReadFull(resp.Body, buf); err != nil {
		t.Fatalf("lecture du flux: %v", err)
	}
	if string(buf) != string(payload) {
		t.Fatalf("recu %q, attendu %q", buf, payload)
	}

	// Le client raccroche : le handler doit rendre la main et se
	// desenregistrer du Hub.
	cancel()
	waitUntil(t, 5*time.Second, func() bool { return h.hub.ListenerCount(stream.ID) == 0 }, "l'auditeur n'a pas ete desenregistre")
}

// Un diffuseur dont la connexion casse en plein direct : le premier morceau
// est diffuse, l'erreur de lecture met fin proprement au broadcast.
func TestStreamHandlerBroadcastStopsOnReadError(t *testing.T) {
	h := newStreamHarness()
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/streams/x/broadcast", &errBodyReader{})
	req = reqWithClaims(req, unitClaims(ownerID, domain.RoleBroadcaster))
	req = reqWithParams(req, "id", stream.ID.String())

	h.handler.Broadcast(rec, req)

	// Pas d'enveloppe d'erreur : la connexion etait en streaming, le handler
	// se contente de journaliser et de rendre la main.
	if rec.Code != http.StatusOK {
		t.Fatalf("statut attendu 200 (aucune ecriture), obtenu %d", rec.Code)
	}
}

// Diffuseur disparu (app tuee, reseau coupe) : sans POST /broadcast de
// remplacement dans le delai de grace, le direct est arrete comme par
// POST /stop et les auditeurs sont deconnectes. Avant, le flux restait
// "live" en base et les auditeurs se connectaient a un direct muet.
func TestStreamHandlerBroadcastAutoStopsWhenBroadcasterGone(t *testing.T) {
	h := newStreamHarnessWithGrace(30 * time.Millisecond)
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)

	listener := streaming.NewClient(uuid.New(), "alice")
	h.hub.Register(stream.ID, listener)

	req := httptest.NewRequest(http.MethodPost, "/streams/x/broadcast", strings.NewReader("quelques octets"))
	req = reqWithClaims(req, unitClaims(ownerID, domain.RoleBroadcaster))
	req = reqWithParams(req, "id", stream.ID.String())
	h.handler.Broadcast(httptest.NewRecorder(), req)

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

// Le diffuseur revient dans le delai de grace (reconnexion apres une
// coupure) : le direct continue, et il n'est arrete qu'une fois la nouvelle
// connexion terminee sans remplacant.
func TestStreamHandlerBroadcastKeepsStreamWhenBroadcasterReturns(t *testing.T) {
	const grace = 80 * time.Millisecond
	h := newStreamHarnessWithGrace(grace)
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)

	newReq := func(body io.Reader) *http.Request {
		req := httptest.NewRequest(http.MethodPost, "/streams/x/broadcast", body)
		req = reqWithClaims(req, unitClaims(ownerID, domain.RoleBroadcaster))
		return reqWithParams(req, "id", stream.ID.String())
	}

	// Premiere connexion, coupee.
	h.handler.Broadcast(httptest.NewRecorder(), newReq(strings.NewReader("premier")))

	// Reconnexion immediate, maintenue ouverte.
	pr, pw := io.Pipe()
	done := make(chan struct{})
	go func() {
		defer close(done)
		h.handler.Broadcast(httptest.NewRecorder(), newReq(pr))
	}()

	time.Sleep(3 * grace)
	if s, _ := h.repo.FindByID(context.Background(), stream.ID); s.Status != domain.StreamStatusLive {
		t.Fatalf("flux arrete alors que le diffuseur est revenu, statut %s", s.Status)
	}

	// Le diffuseur raccroche pour de bon.
	_ = pw.Close()
	<-done
	waitUntil(t, 5*time.Second, func() bool {
		s, err := h.repo.FindByID(context.Background(), stream.ID)
		return err == nil && s.Status == domain.StreamStatusEnded
	}, "le flux n'a pas ete arrete apres la derniere deconnexion")
}

// Fin de direct normale : le corps se termine par EOF apres quelques octets.
func TestStreamHandlerBroadcastReadsUntilEOF(t *testing.T) {
	h := newStreamHarness()
	ownerID := uuid.New()
	stream := h.liveStream(t, ownerID)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/streams/x/broadcast", strings.NewReader("quelques octets"))
	req = reqWithClaims(req, unitClaims(ownerID, domain.RoleBroadcaster))
	req = reqWithParams(req, "id", stream.ID.String())

	h.handler.Broadcast(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("statut attendu 200 (aucune ecriture), obtenu %d", rec.Code)
	}
}
