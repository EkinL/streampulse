package integration_test

import (
	"bufio"
	"context"
	"encoding/base64"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
)

// readSSEData lit le prochain evenement SSE et rend le contenu de sa ligne
// `data:`. Le contexte de la requete borne l'attente.
func readSSEData(t *testing.T, r *bufio.Reader) string {
	t.Helper()
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			t.Fatalf("lecture SSE interrompue: %v", err)
		}
		if strings.HasPrefix(line, "data: ") {
			return strings.TrimSpace(strings.TrimPrefix(line, "data: "))
		}
	}
}

// UC-10 + UC-05 : un diffuseur cree, demarre, diffuse et arrete un flux
// pendant qu'un auditeur l'ecoute en SSE.
func TestStreams_LifecycleWithLiveListener(t *testing.T) {
	s := newSuite(t)
	bc := s.newAccount(t, domain.RoleBroadcaster)
	listener := s.newAccount(t, domain.RoleUser)

	d := s.do(t, http.MethodPost, "/streams", bc.Access, map[string]any{
		"title": "Soiree jazz", "description": "en direct du studio",
	}).expect(t, http.StatusCreated, "").data(t)
	id := str(d, "id")
	if str(d, "status") != "idle" || str(d, "owner_id") != bc.ID || str(d, "format") != "mp3" {
		t.Fatalf("flux cree inattendu: %v", d)
	}

	s.do(t, http.MethodGet, "/streams/"+id+"/listen", listener.Access, nil).
		expect(t, http.StatusBadRequest, "STREAM_NOT_LIVE")

	d = s.do(t, http.MethodPost, "/streams/"+id+"/start", bc.Access, nil).expect(t, http.StatusOK, "").data(t)
	if str(d, "status") != "live" {
		t.Fatalf("status apres start: %v", d)
	}
	s.do(t, http.MethodPost, "/streams/"+id+"/start", bc.Access, nil).expect(t, http.StatusConflict, "CONFLICT")

	// Auditeur : connexion SSE longue, bornee a 15 s pour ne jamais bloquer
	// la suite en cas de regression.
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.srv.URL+"/streams/"+id+"/listen", nil)
	if err != nil {
		t.Fatalf("requete listen: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+listener.Access)
	resp, err := s.client.Do(req)
	if err != nil {
		t.Fatalf("connexion listen: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("listen: status %d", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("Content-Type %q, attendu text/event-stream", ct)
	}
	sse := bufio.NewReader(resp.Body)
	if hello := readSSEData(t, sse); !strings.Contains(hello, `"status":"connected"`) {
		t.Fatalf("premier evenement inattendu: %s", hello)
	}

	d = s.do(t, http.MethodGet, "/streams/"+id+"/listeners", listener.Access, nil).expect(t, http.StatusOK, "").data(t)
	if count, _ := d["count"].(float64); count != 1 {
		t.Fatalf("1 auditeur attendu, obtenu %v", d)
	}
	listeners, _ := d["listeners"].([]any)
	if first, _ := listeners[0].(map[string]any); str(first, "username") != listener.Username {
		t.Fatalf("auditeur inattendu: %v", listeners)
	}
	d = s.do(t, http.MethodGet, "/streams/"+id, "", nil).expect(t, http.StatusOK, "").data(t)
	if n, _ := d["listener_count"].(float64); n != 1 {
		t.Fatalf("listener_count public = %v, attendu 1", d["listener_count"])
	}

	// Diffusion : le corps du POST est relaye tel quel, encode en base64
	// dans le flux SSE.
	chunk := []byte("audio-chunk-0001")
	s.do(t, http.MethodPost, "/streams/"+id+"/broadcast", bc.Access, chunk).expect(t, http.StatusOK, "")
	got, err := base64.StdEncoding.DecodeString(readSSEData(t, sse))
	if err != nil {
		t.Fatalf("payload SSE non base64: %v", err)
	}
	if string(got) != string(chunk) {
		t.Fatalf("auditeur a recu %q, attendu %q", got, chunk)
	}

	// L'auditeur quitte : le Hub le retire.
	cancel()
	waitFor(t, 3*time.Second, func() bool { return s.hub.ListenerCount(uuid.MustParse(id)) == 0 },
		"l'auditeur deconnecte doit disparaitre du Hub")

	d = s.do(t, http.MethodPost, "/streams/"+id+"/stop", bc.Access, nil).expect(t, http.StatusOK, "").data(t)
	if str(d, "status") != "stopped" {
		t.Fatalf("status apres stop: %v", d)
	}
	d = s.do(t, http.MethodGet, "/streams/"+id, "", nil).expect(t, http.StatusOK, "").data(t)
	if str(d, "status") != "ended" {
		t.Fatalf("un flux arrete doit etre `ended`, obtenu %v", d)
	}
	s.do(t, http.MethodGet, "/streams/"+id+"/listen", listener.Access, nil).
		expect(t, http.StatusBadRequest, "STREAM_NOT_LIVE")
}

// Propriete et cas d'erreur : un autre diffuseur, un admin, un identifiant
// inconnu ou invalide.
func TestStreams_OwnershipAndErrors(t *testing.T) {
	s := newSuite(t)
	owner := s.newAccount(t, domain.RoleBroadcaster)
	other := s.newAccount(t, domain.RoleBroadcaster)
	admin := s.newAccount(t, domain.RoleAdmin)
	id := s.createStream(t, owner, "Flux prive")
	unknown := uuid.NewString()
	update := map[string]any{"title": "Pirate", "description": ""}

	t.Run("un autre diffuseur ne controle pas le flux", func(t *testing.T) {
		s.do(t, http.MethodPost, "/streams/"+id+"/start", other.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodPost, "/streams/"+id+"/stop", other.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodPut, "/streams/"+id, other.Access, update).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodPost, "/streams/"+id+"/broadcast", other.Access, []byte("x")).expect(t, http.StatusForbidden, "FORBIDDEN")
	})

	t.Run("l'admin n'est pas proprietaire non plus", func(t *testing.T) {
		s.do(t, http.MethodPut, "/streams/"+id, admin.Access, update).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodPost, "/streams/"+id+"/start", admin.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")
	})

	t.Run("diffuser sur un flux non demarre", func(t *testing.T) {
		s.do(t, http.MethodPost, "/streams/"+id+"/broadcast", owner.Access, []byte("x")).
			expect(t, http.StatusBadRequest, "STREAM_NOT_LIVE")
	})

	t.Run("identifiant inconnu", func(t *testing.T) {
		s.do(t, http.MethodGet, "/streams/"+unknown, "", nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodPost, "/streams/"+unknown+"/start", owner.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodPost, "/streams/"+unknown+"/stop", owner.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodPut, "/streams/"+unknown, owner.Access, update).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodGet, "/streams/"+unknown+"/listen", owner.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodPost, "/streams/"+unknown+"/broadcast", owner.Access, []byte("x")).expect(t, http.StatusNotFound, "NOT_FOUND")
	})

	t.Run("identifiant invalide", func(t *testing.T) {
		s.do(t, http.MethodGet, "/streams/pas-un-uuid", "", nil).expect(t, http.StatusBadRequest, "BAD_REQUEST")
		s.do(t, http.MethodPost, "/streams/pas-un-uuid/start", owner.Access, nil).expect(t, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("validation a la creation", func(t *testing.T) {
		s.do(t, http.MethodPost, "/streams", owner.Access, map[string]any{"description": "sans titre"}).
			expect(t, http.StatusBadRequest, "BAD_REQUEST")
		s.do(t, http.MethodPost, "/streams", owner.Access, map[string]any{"title": "x", "owner_id": admin.ID}).
			expect(t, http.StatusBadRequest, "BAD_REQUEST")
		s.do(t, http.MethodPost, "/streams", owner.Access, "not json").
			expect(t, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("le proprietaire modifie son flux", func(t *testing.T) {
		d := s.do(t, http.MethodPut, "/streams/"+id, owner.Access, map[string]any{"title": "Renomme", "description": "maj"}).
			expect(t, http.StatusOK, "").data(t)
		if str(d, "title") != "Renomme" || str(d, "description") != "maj" {
			t.Fatalf("mise a jour non appliquee: %v", d)
		}
	})
}

// Pagination de la liste publique : meta.page / perPage / total.
func TestStreams_ListPagination(t *testing.T) {
	s := newSuite(t)
	bc := s.newAccount(t, domain.RoleBroadcaster)
	for i := 0; i < 3; i++ {
		s.createStream(t, bc, "Flux pagine")
	}

	r := s.do(t, http.MethodGet, "/streams?page=1&per_page=2", "", nil).expect(t, http.StatusOK, "")
	if n := len(r.list(t)); n != 2 {
		t.Fatalf("2 elements attendus, obtenu %d", n)
	}
	m := r.meta(t)
	if m["page"].(float64) != 1 || m["perPage"].(float64) != 2 || m["total"].(float64) < 3 {
		t.Fatalf("meta de pagination inattendue: %v", m)
	}
	if str(m, "requestId") == "" || r.Header.Get("X-Request-ID") != str(m, "requestId") {
		t.Fatalf("meta.requestId doit egaler l'en-tete X-Request-ID: %v / %q", m, r.Header.Get("X-Request-ID"))
	}
}
