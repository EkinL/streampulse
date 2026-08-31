package integration_test

import (
	"net/http"
	"testing"

	"github.com/streampulse/backend/internal/domain"
)

// Matrice role x endpoint : pour chaque route representative, le code HTTP
// attendu pour un anonyme, un user, un broadcaster et un admin. C'est la
// verification directe des exigences 1.2 a 1.5 du sujet.
func TestRBAC_EndpointMatrix(t *testing.T) {
	s := newSuite(t)
	user := s.newAccount(t, domain.RoleUser)
	bc := s.newAccount(t, domain.RoleBroadcaster)
	admin := s.newAccount(t, domain.RoleAdmin)
	streamID := s.createStream(t, bc, "Flux matrice")
	musicID := s.addMusicByURL(t, bc, "Morceau matrice", "Artiste")
	// Compte jetable : la ligne DELETE /admin/users/{id} le supprime pour de
	// bon quand c'est l'admin qui appelle.
	doomed := s.newAccount(t, domain.RoleUser)

	tokens := map[string]string{
		"anonymous": "", "user": user.Access, "broadcaster": bc.Access, "admin": admin.Access,
	}
	const (
		ok, created, unauth, forbidden = http.StatusOK, http.StatusCreated, http.StatusUnauthorized, http.StatusForbidden
	)
	all := map[string]int{"anonymous": ok, "user": ok, "broadcaster": ok, "admin": ok}
	authenticated := map[string]int{"anonymous": unauth, "user": ok, "broadcaster": ok, "admin": ok}
	broadcasterOnly := map[string]int{"anonymous": unauth, "user": forbidden, "broadcaster": created, "admin": created}
	adminOnly := map[string]int{"anonymous": unauth, "user": forbidden, "broadcaster": forbidden, "admin": ok}

	cases := []struct {
		method, path string
		body         any
		want         map[string]int
	}{
		// Consultation anonyme (exigence 1.2)
		{http.MethodGet, "/streams", nil, all},
		{http.MethodGet, "/streams/" + streamID, nil, all},
		{http.MethodGet, "/music", nil, all},
		{http.MethodGet, "/music/" + musicID, nil, all},
		{http.MethodGet, "/search?q=matrice", nil, all},
		// User : ecoute, favoris, playlists (exigence 1.3)
		{http.MethodGet, "/streams/" + streamID + "/listeners", nil, authenticated},
		{http.MethodGet, "/playlists", nil, authenticated},
		{http.MethodGet, "/favorites", nil, authenticated},
		{http.MethodGet, "/music/favorites", nil, authenticated},
		{http.MethodGet, "/music/favorites/ids", nil, authenticated},
		// Tout compte connecte lit ses propres donnees (RGPD, docs/rgpd.md)
		{http.MethodGet, "/users/me", nil, authenticated},
		// Diffuseur : flux et sources audio (exigence 1.4)
		{http.MethodPost, "/streams", map[string]any{"title": "Nouveau flux"}, broadcasterOnly},
		{http.MethodPost, "/music", map[string]any{"title": "Nouveau", "url": "https://cdn.test/n.mp3"}, broadcasterOnly},
		// Propriete distincte du role : l'admin a le role suffisant mais
		// n'est pas proprietaire du flux.
		{http.MethodPut, "/streams/" + streamID, map[string]any{"title": "Renomme", "description": ""},
			map[string]int{"anonymous": unauth, "user": forbidden, "broadcaster": ok, "admin": forbidden}},
		// Admin : comptes et metriques (exigence 1.5)
		{http.MethodGet, "/admin/users", nil, adminOnly},
		{http.MethodPut, "/admin/users/" + user.ID + "/role", map[string]any{"role": "user"}, adminOnly},
		{http.MethodGet, "/metrics", nil, adminOnly},
		{http.MethodDelete, "/admin/users/" + doomed.ID, nil, adminOnly},
	}

	for _, tc := range cases {
		for _, role := range []string{"anonymous", "user", "broadcaster", "admin"} {
			t.Run(role+" "+tc.method+" "+tc.path, func(t *testing.T) {
				r := s.do(t, tc.method, tc.path, tokens[role], tc.body)
				if r.Status != tc.want[role] {
					t.Fatalf("status %d, attendu %d. Corps: %s", r.Status, tc.want[role], r.Raw)
				}
				switch r.Status {
				case unauth:
					if r.errorCode(t) != "UNAUTHORIZED" {
						t.Fatalf("code attendu UNAUTHORIZED: %s", r.Raw)
					}
				case forbidden:
					if r.errorCode(t) != "FORBIDDEN" {
						t.Fatalf("code attendu FORBIDDEN: %s", r.Raw)
					}
				}
			})
		}
	}
}
