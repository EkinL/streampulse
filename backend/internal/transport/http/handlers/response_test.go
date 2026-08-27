package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/streampulse/backend/internal/transport/http/middleware"
)

// TestNewMetaReusesRequestID est le coeur de la correlation : l'identifiant
// renvoye au client doit etre celui pose par la chaine de middlewares, et non
// un uuid neuf genere a chaque reponse.
func TestNewMetaReusesRequestID(t *testing.T) {
	const reqID = "streampulse/abc123-000001"

	rec := httptest.NewRecorder()
	rec.Header().Set(middleware.RequestIDHeaderName, reqID)

	if got := newMeta(rec).RequestID; got != reqID {
		t.Errorf("meta.requestId = %q, want %q", got, reqID)
	}
}

// TestNewMetaFallsBackWhenHeaderAbsent couvre l'appel direct d'un handler hors
// chaine de middlewares : le champ ne doit pas etre vide.
func TestNewMetaFallsBackWhenHeaderAbsent(t *testing.T) {
	first := newMeta(httptest.NewRecorder()).RequestID
	if first == "" {
		t.Fatal("meta.requestId ne doit jamais etre vide")
	}

	// Sans header, deux reponses sont independantes : le repli genere bien un
	// identifiant a chaque fois plutot qu'une constante.
	if second := newMeta(httptest.NewRecorder()).RequestID; second == first {
		t.Error("le repli doit generer un identifiant par reponse")
	}
}

func TestNewMetaSetsUTCTimestamp(t *testing.T) {
	meta := newMeta(httptest.NewRecorder())
	if meta.Timestamp.IsZero() {
		t.Fatal("meta.timestamp est vide")
	}
	if name, _ := meta.Timestamp.Zone(); name != "UTC" {
		t.Errorf("meta.timestamp est en %q, want UTC", name)
	}
}

// TestRespondHelpersPropagateRequestID verifie les trois helpers d'un coup :
// tous doivent reprendre l'identifiant, y compris respondError, qui sert les
// reponses les plus susceptibles d'etre citees dans un rapport de bug.
func TestRespondHelpersPropagateRequestID(t *testing.T) {
	const reqID = "streampulse/abc123-000042"

	for _, tc := range []struct {
		name       string
		respond    func(w http.ResponseWriter)
		wantStatus int
	}{
		{
			name:       "respondJSON",
			respond:    func(w http.ResponseWriter) { respondJSON(w, http.StatusOK, map[string]string{"status": "ok"}) },
			wantStatus: http.StatusOK,
		},
		{
			name:       "respondPaginated",
			respond:    func(w http.ResponseWriter) { respondPaginated(w, []string{}, 2, 20, 150) },
			wantStatus: http.StatusOK,
		},
		{
			name:       "respondError",
			respond:    func(w http.ResponseWriter) { respondError(w, http.StatusNotFound, "NOT_FOUND", "stream not found") },
			wantStatus: http.StatusNotFound,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			rec.Header().Set(middleware.RequestIDHeaderName, reqID)
			tc.respond(rec)

			if rec.Code != tc.wantStatus {
				t.Fatalf("status %d, want %d", rec.Code, tc.wantStatus)
			}
			var body struct {
				Meta Meta `json:"meta"`
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
				t.Fatalf("corps illisible: %v", err)
			}
			if body.Meta.RequestID != reqID {
				t.Errorf("meta.requestId = %q, want %q", body.Meta.RequestID, reqID)
			}
		})
	}
}

// TestRespondPaginatedKeepsPagination : newMeta ne doit pas ecraser les champs
// de pagination.
func TestRespondPaginatedKeepsPagination(t *testing.T) {
	rec := httptest.NewRecorder()
	respondPaginated(rec, []string{"a"}, 2, 20, 150)

	var body struct {
		Meta Meta `json:"meta"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("corps illisible: %v", err)
	}
	if body.Meta.Page != 2 || body.Meta.PerPage != 20 || body.Meta.Total != 150 {
		t.Errorf("meta = page %d, perPage %d, total %d ; want 2/20/150",
			body.Meta.Page, body.Meta.PerPage, body.Meta.Total)
	}
}
