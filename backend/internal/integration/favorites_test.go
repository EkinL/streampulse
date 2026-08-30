package integration_test

import (
	"net/http"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
)

// UC-06 : favoris de flux.
func TestFavorites_Streams(t *testing.T) {
	s := newSuite(t)
	u := s.newAccount(t, domain.RoleUser)
	bc := s.newAccount(t, domain.RoleBroadcaster)
	id := s.createStream(t, bc, "Flux favori")

	for i := 0; i < 2; i++ { // idempotent
		s.do(t, http.MethodPost, "/favorites/"+id, u.Access, nil).expect(t, http.StatusCreated, "")
	}
	r := s.do(t, http.MethodGet, "/favorites", u.Access, nil).expect(t, http.StatusOK, "")
	if !containsID(r.list(t), id) || r.meta(t)["total"].(float64) != 1 {
		t.Fatalf("le flux doit apparaitre une seule fois: %s", r.Raw)
	}

	s.do(t, http.MethodDelete, "/favorites/"+id, u.Access, nil).expect(t, http.StatusOK, "")
	s.do(t, http.MethodDelete, "/favorites/"+id, u.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
	if r := s.do(t, http.MethodGet, "/favorites", u.Access, nil).expect(t, http.StatusOK, ""); len(r.list(t)) != 0 {
		t.Fatalf("liste non vide apres retrait: %s", r.Raw)
	}

	s.do(t, http.MethodPost, "/favorites/"+uuid.NewString(), u.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
	s.do(t, http.MethodPost, "/favorites/pas-un-uuid", u.Access, nil).expect(t, http.StatusBadRequest, "BAD_REQUEST")
}

// UC-07 : favoris de morceaux.
func TestFavorites_Music(t *testing.T) {
	s := newSuite(t)
	u := s.newAccount(t, domain.RoleUser)
	bc := s.newAccount(t, domain.RoleBroadcaster)
	id := s.addMusicByURL(t, bc, "Morceau favori", "Artiste")

	s.do(t, http.MethodPost, "/music/"+id+"/favorite", u.Access, nil).expect(t, http.StatusCreated, "")

	d := s.do(t, http.MethodGet, "/music/favorites/ids", u.Access, nil).expect(t, http.StatusOK, "").data(t)
	ids, _ := d["ids"].([]any)
	if len(ids) != 1 || ids[0] != id {
		t.Fatalf("ids = %v, attendu [%s]", ids, id)
	}
	if r := s.do(t, http.MethodGet, "/music/favorites", u.Access, nil).expect(t, http.StatusOK, ""); !containsID(r.list(t), id) {
		t.Fatalf("le morceau doit apparaitre dans la liste: %s", r.Raw)
	}

	s.do(t, http.MethodDelete, "/music/"+id+"/favorite", u.Access, nil).expect(t, http.StatusOK, "")
	s.do(t, http.MethodDelete, "/music/"+id+"/favorite", u.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
	s.do(t, http.MethodPost, "/music/"+uuid.NewString()+"/favorite", u.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
	s.do(t, http.MethodPost, "/music/pas-un-uuid/favorite", u.Access, nil).expect(t, http.StatusBadRequest, "BAD_REQUEST")
}
