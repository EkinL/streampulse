package integration_test

import (
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
)

// UC-12 : gestion des comptes par l'administrateur.
func TestAdmin_UsersAndRoles(t *testing.T) {
	s := newSuite(t)
	admin := s.newAccount(t, domain.RoleAdmin)
	u := s.newAccount(t, domain.RoleUser)

	t.Run("liste des comptes", func(t *testing.T) {
		r := s.do(t, http.MethodGet, "/admin/users?per_page=100", admin.Access, nil).expect(t, http.StatusOK, "")
		users := r.list(t)
		if !containsID(users, u.ID) || r.meta(t)["total"].(float64) < 2 {
			t.Fatalf("la liste doit contenir le compte cree: %s", r.Raw)
		}
		for _, raw := range users {
			item, _ := raw.(map[string]any)
			for _, forbidden := range []string{"password", "password_hash"} {
				if _, leaked := item[forbidden]; leaked {
					t.Fatalf("%s expose dans la liste admin", forbidden)
				}
			}
		}
		r = s.do(t, http.MethodGet, "/admin/users?page=1&per_page=1", admin.Access, nil).expect(t, http.StatusOK, "")
		if len(r.list(t)) != 1 || r.meta(t)["perPage"].(float64) != 1 {
			t.Fatalf("pagination non respectee: %s", r.Raw)
		}
	})

	t.Run("changement de role refuse", func(t *testing.T) {
		s.do(t, http.MethodPut, "/admin/users/"+u.ID+"/role", admin.Access, map[string]any{"role": "sorcier"}).expect(t, http.StatusBadRequest, "BAD_REQUEST")
		s.do(t, http.MethodPut, "/admin/users/"+u.ID+"/role", admin.Access, map[string]any{"role": "admin", "id": u.ID}).expect(t, http.StatusBadRequest, "BAD_REQUEST")
		s.do(t, http.MethodPut, "/admin/users/"+uuid.NewString()+"/role", admin.Access, map[string]any{"role": "user"}).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodPut, "/admin/users/pas-un-uuid/role", admin.Access, map[string]any{"role": "user"}).expect(t, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("promotion : effective au jeton suivant", func(t *testing.T) {
		d := s.do(t, http.MethodPut, "/admin/users/"+u.ID+"/role", admin.Access, map[string]any{"role": "broadcaster"}).
			expect(t, http.StatusOK, "").data(t)
		if str(d, "status") != "updated" {
			t.Fatalf("reponse inattendue: %v", d)
		}
		// Les claims sont figees a l'emission (ADR 006) : l'ancien jeton
		// reste `user`.
		s.do(t, http.MethodPost, "/streams", u.Access, map[string]any{"title": "Trop tot"}).expect(t, http.StatusForbidden, "FORBIDDEN")
		access, _ := s.login(t, u.Email)
		s.do(t, http.MethodPost, "/streams", access, map[string]any{"title": "Premier flux"}).expect(t, http.StatusCreated, "")
	})
}

// UC-13 : l'administrateur lit les metriques globales.
func TestAdmin_MetricsExposePlatformGauges(t *testing.T) {
	s := newSuite(t)
	admin := s.newAccount(t, domain.RoleAdmin)

	r := s.do(t, http.MethodGet, "/metrics", admin.Access, nil)
	if r.Status != http.StatusOK {
		t.Fatalf("status %d", r.Status)
	}
	body := string(r.Raw)
	for _, metric := range []string{"active_streams", "active_listeners", "stream_disconnections_total", "stream_bytes_sent_total", "listener_sessions_total", "sessions_with_chunk_loss_total"} {
		if !strings.Contains(body, metric) {
			t.Errorf("metrique %s absente de /metrics", metric)
		}
	}
}
