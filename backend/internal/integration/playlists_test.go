package integration_test

import (
	"net/http"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
)

func trackOrder(t *testing.T, r response) []string {
	t.Helper()
	tracks, _ := r.data(t)["tracks"].([]any)
	ids := make([]string, 0, len(tracks))
	for i, raw := range tracks {
		tr, _ := raw.(map[string]any)
		if pos, _ := tr["position"].(float64); int(pos) != i {
			t.Fatalf("positions non contigues: %v", tracks)
		}
		ids = append(ids, str(tr, "id"))
	}
	return ids
}

func equalOrder(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// UC-08 / UC-09 : CRUD de playlist et logique de file d'attente.
func TestPlaylists_QueueManagement(t *testing.T) {
	s := newSuite(t)
	u := s.newAccount(t, domain.RoleUser)

	d := s.do(t, http.MethodPost, "/playlists", u.Access, map[string]any{"name": "Ma file", "is_public": false}).
		expect(t, http.StatusCreated, "").data(t)
	id := str(d, "id")
	if str(d, "owner_id") != u.ID || d["is_public"] != false {
		t.Fatalf("playlist creee inattendue: %v", d)
	}

	var ids []string
	for i, title := range []string{"Piste A", "Piste B", "Piste C"} {
		d := s.do(t, http.MethodPost, "/playlists/"+id+"/tracks", u.Access, map[string]any{
			"title": title, "url": "https://cdn.test/" + title + ".mp3", "duration": 60,
		}).expect(t, http.StatusCreated, "").data(t)
		if pos, _ := d["position"].(float64); int(pos) != i {
			t.Fatalf("piste %d inseree en position %v", i, d["position"])
		}
		ids = append(ids, str(d, "id"))
	}
	if got := trackOrder(t, s.do(t, http.MethodGet, "/playlists/"+id, u.Access, nil).expect(t, http.StatusOK, "")); !equalOrder(got, ids) {
		t.Fatalf("ordre initial %v, attendu %v", got, ids)
	}

	t.Run("reordonnancement complet", func(t *testing.T) {
		want := []string{ids[2], ids[0], ids[1]}
		r := s.do(t, http.MethodPut, "/playlists/"+id+"/tracks", u.Access, map[string]any{"track_ids": want}).expect(t, http.StatusOK, "")
		if got := trackOrder(t, r); !equalOrder(got, want) {
			t.Fatalf("ordre %v, attendu %v", got, want)
		}
		ids = want
	})

	t.Run("listes refusees, ordre intact", func(t *testing.T) {
		cases := []struct {
			name   string
			body   any
			status int
			code   string
		}{
			{"incomplete", map[string]any{"track_ids": ids[:2]}, http.StatusBadRequest, "BAD_REQUEST"},
			{"vide", map[string]any{"track_ids": []string{}}, http.StatusBadRequest, "BAD_REQUEST"},
			{"doublon", map[string]any{"track_ids": []string{ids[0], ids[0], ids[1]}}, http.StatusBadRequest, "BAD_REQUEST"},
			{"id invalide", map[string]any{"track_ids": []string{"nope", ids[1], ids[2]}}, http.StatusBadRequest, "BAD_REQUEST"},
			{"piste etrangere", map[string]any{"track_ids": []string{ids[0], ids[1], uuid.NewString()}}, http.StatusNotFound, "NOT_FOUND"},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				s.do(t, http.MethodPut, "/playlists/"+id+"/tracks", u.Access, tc.body).expect(t, tc.status, tc.code)
				got := trackOrder(t, s.do(t, http.MethodGet, "/playlists/"+id, u.Access, nil).expect(t, http.StatusOK, ""))
				if !equalOrder(got, ids) {
					t.Fatalf("la playlist a change malgre le refus: %v", got)
				}
			})
		}
	})

	t.Run("suppression et compactage", func(t *testing.T) {
		d := s.do(t, http.MethodDelete, "/playlists/"+id+"/tracks/"+ids[1], u.Access, nil).expect(t, http.StatusOK, "").data(t)
		if str(d, "status") != "removed" {
			t.Fatalf("reponse inattendue: %v", d)
		}
		want := []string{ids[0], ids[2]}
		if got := trackOrder(t, s.do(t, http.MethodGet, "/playlists/"+id, u.Access, nil).expect(t, http.StatusOK, "")); !equalOrder(got, want) {
			t.Fatalf("ordre apres suppression %v, attendu %v", got, want)
		}
		s.do(t, http.MethodDelete, "/playlists/"+id+"/tracks/"+ids[1], u.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
	})

	t.Run("mise a jour et liste", func(t *testing.T) {
		d := s.do(t, http.MethodPut, "/playlists/"+id, u.Access, map[string]any{"name": "Renommee", "is_public": true}).
			expect(t, http.StatusOK, "").data(t)
		if str(d, "name") != "Renommee" || d["is_public"] != true {
			t.Fatalf("mise a jour non appliquee: %v", d)
		}
		r := s.do(t, http.MethodGet, "/playlists", u.Access, nil).expect(t, http.StatusOK, "")
		if !containsID(r.list(t), id) || r.meta(t)["total"].(float64) != 1 {
			t.Fatalf("la liste doit contenir la seule playlist de l'utilisateur: %s", r.Raw)
		}
	})

	t.Run("suppression de la playlist", func(t *testing.T) {
		s.do(t, http.MethodDelete, "/playlists/"+id, u.Access, nil).expect(t, http.StatusOK, "")
		s.do(t, http.MethodGet, "/playlists/"+id, u.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodDelete, "/playlists/"+id, u.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodPost, "/playlists/"+id+"/tracks", u.Access, map[string]any{"title": "x", "url": "u"}).
			expect(t, http.StatusNotFound, "NOT_FOUND")
	})
}

// Visibilite : une playlist privee n'existe pas pour les autres (404, pas
// 403) ; une playlist publique est lisible mais pas modifiable par un tiers.
func TestPlaylists_VisibilityAndOwnership(t *testing.T) {
	s := newSuite(t)
	a := s.newAccount(t, domain.RoleUser)
	b := s.newAccount(t, domain.RoleUser)

	private := str(s.do(t, http.MethodPost, "/playlists", a.Access, map[string]any{"name": "Privee"}).
		expect(t, http.StatusCreated, "").data(t), "id")
	public := str(s.do(t, http.MethodPost, "/playlists", a.Access, map[string]any{"name": "Publique", "is_public": true}).
		expect(t, http.StatusCreated, "").data(t), "id")

	s.do(t, http.MethodGet, "/playlists/"+private, b.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
	s.do(t, http.MethodGet, "/playlists/"+public, b.Access, nil).expect(t, http.StatusOK, "")

	for _, target := range []string{private, public} {
		s.do(t, http.MethodPut, "/playlists/"+target, b.Access, map[string]any{"name": "Volee"}).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodDelete, "/playlists/"+target, b.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodPost, "/playlists/"+target+"/tracks", b.Access, map[string]any{"title": "x", "url": "u"}).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodPut, "/playlists/"+target+"/tracks", b.Access, map[string]any{"track_ids": []string{uuid.NewString()}}).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodDelete, "/playlists/"+target+"/tracks/"+uuid.NewString(), b.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")
	}

	// La liste de B ne montre pas les playlists de A.
	if r := s.do(t, http.MethodGet, "/playlists", b.Access, nil).expect(t, http.StatusOK, ""); len(r.list(t)) != 0 {
		t.Fatalf("B ne doit voir aucune playlist: %s", r.Raw)
	}

	s.do(t, http.MethodPost, "/playlists", a.Access, map[string]any{"is_public": true}).expect(t, http.StatusBadRequest, "BAD_REQUEST")
	s.do(t, http.MethodGet, "/playlists/pas-un-uuid", a.Access, nil).expect(t, http.StatusBadRequest, "BAD_REQUEST")
}
