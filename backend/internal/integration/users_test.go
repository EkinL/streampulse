package integration_test

import (
	"context"
	"net/http"
	"os"
	"path"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
)

// UC-20 : droit d'acces et droit a l'effacement (RGPD, docs/rgpd.md).
// La personne lit tout ce que la plateforme conserve sur elle, puis
// supprime son compte ; il ne doit rien rester, ni en base ni d'utilisable
// avec ses anciens jetons.
func TestUsers_AccessAndErasure(t *testing.T) {
	s := newSuite(t)
	bc := s.newAccount(t, domain.RoleBroadcaster)
	streamID := s.createStream(t, bc, "Flux a effacer")
	musicID := s.addMusicByURL(t, bc, "Morceau a effacer", "Artiste")
	s.do(t, http.MethodPost, "/playlists", bc.Access, map[string]any{"name": "Playlist a effacer", "is_public": false}).expect(t, http.StatusCreated, "")
	s.do(t, http.MethodPost, "/favorites/"+streamID, bc.Access, nil).expect(t, http.StatusCreated, "")

	// Un morceau verse (pas seulement ajoute par URL) : la suppression du
	// compte doit aussi retirer le fichier de uploads/, sans quoi il reste
	// servi par son URL pour qui la connait (limite connue, docs/rgpd.md).
	uploaded := s.upload(t, bc.Access, map[string]string{"title": "Repetition a effacer", "artist": "Test"}, "repetition.mp3", []byte("audio-a-effacer")).
		expect(t, http.StatusCreated, "").data(t)
	uploadedPath := path.Join(uploadDir, path.Base(str(uploaded, "url")))
	if _, err := os.Stat(uploadedPath); err != nil {
		t.Fatalf("le fichier uploade doit exister sur disque avant la suppression du compte: %v", err)
	}

	// Le flux est en direct avec un auditeur connecte : la suppression du
	// compte doit le couper, pas seulement effacer la ligne en base.
	s.do(t, http.MethodPost, "/streams/"+streamID+"/start", bc.Access, nil).expect(t, http.StatusOK, "")
	listener := s.newAccount(t, domain.RoleUser)
	listenCtx, stopListening := context.WithCancel(context.Background())
	defer stopListening()
	req, err := http.NewRequestWithContext(listenCtx, http.MethodGet, s.srv.URL+"/streams/"+streamID+"/listen", nil)
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
	sid, _ := uuid.Parse(streamID)
	waitFor(t, 2*time.Second, func() bool { return s.hub.ListenerCount(sid) == 1 }, "auditeur non enregistre dans le hub")

	t.Run("droit d'acces : GET /users/me", func(t *testing.T) {
		d := s.do(t, http.MethodGet, "/users/me", bc.Access, nil).expect(t, http.StatusOK, "").data(t)
		if str(d, "id") != bc.ID || str(d, "email") != bc.Email || str(d, "username") != bc.Username || str(d, "role") != "broadcaster" {
			t.Fatalf("profil inattendu: %v", d)
		}
		if str(d, "created_at") == "" || str(d, "updated_at") == "" {
			t.Fatalf("les dates de creation et de mise a jour font partie des donnees conservees: %v", d)
		}
		for _, forbidden := range []string{"password", "password_hash"} {
			if _, leaked := d[forbidden]; leaked {
				t.Fatalf("%s expose dans le profil", forbidden)
			}
		}
	})

	t.Run("sans jeton : 401", func(t *testing.T) {
		s.do(t, http.MethodGet, "/users/me", "", nil).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")
		s.do(t, http.MethodDelete, "/users/me", "", nil).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")
	})

	t.Run("droit a l'effacement : DELETE /users/me", func(t *testing.T) {
		d := s.do(t, http.MethodDelete, "/users/me", bc.Access, nil).expect(t, http.StatusOK, "").data(t)
		if str(d, "status") != "deleted" {
			t.Fatalf("reponse inattendue: %v", d)
		}

		// Le jeton d'acces est encore valide cryptographiquement (ADR 006)
		// mais ne designe plus personne.
		s.do(t, http.MethodGet, "/users/me", bc.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodDelete, "/users/me", bc.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		// Le refresh token est parti avec le compte : impossible de
		// prolonger la session.
		s.do(t, http.MethodPost, "/auth/refresh", "", map[string]any{"refresh_token": bc.Refresh}).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")
		// Et plus de connexion possible.
		s.do(t, http.MethodPost, "/auth/login", "", map[string]any{"email": bc.Email, "password": password}).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")
		// Le direct est coupe : plus personne n'ecoute le flux du compte efface.
		waitFor(t, 2*time.Second, func() bool { return s.hub.ListenerCount(sid) == 0 }, "le direct du compte supprime a encore des auditeurs")
	})

	t.Run("plus rien en base", func(t *testing.T) {
		ctx := context.Background()
		id, _ := uuid.Parse(bc.ID)
		if _, err := s.users.FindByID(ctx, id); err == nil {
			t.Fatal("le compte existe encore en base")
		}
		for table, column := range map[string]string{
			"refresh_tokens": "user_id", "streams": "owner_id", "playlists": "owner_id",
			"favorites": "user_id", "music": "uploaded_by", "music_favorites": "user_id",
		} {
			var n int
			if err := s.pool.QueryRow(ctx, "SELECT COUNT(*) FROM "+table+" WHERE "+column+" = $1", id).Scan(&n); err != nil {
				t.Fatalf("comptage %s: %v", table, err)
			}
			if n != 0 {
				t.Errorf("%d ligne(s) restante(s) dans %s pour le compte supprime", n, table)
			}
		}
		// Ses ressources publiques ont disparu du catalogue.
		s.do(t, http.MethodGet, "/streams/"+streamID, "", nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodGet, "/music/"+musicID, "", nil).expect(t, http.StatusNotFound, "NOT_FOUND")

		// Le fichier verse a disparu du disque, pas seulement sa ligne en
		// base (limite connue, docs/rgpd.md).
		if _, err := os.Stat(uploadedPath); !os.IsNotExist(err) {
			t.Fatalf("le fichier uploade doit avoir disparu du disque, err=%v", err)
		}
	})

	t.Run("l'email est libere", func(t *testing.T) {
		s.do(t, http.MethodPost, "/auth/register", "", map[string]any{
			"email": bc.Email, "username": "renaissance", "password": password,
		}).expect(t, http.StatusCreated, "")
	})
}

// UC-22 : droit de rectification (RGPD, docs/rgpd.md). La personne change
// son email et son nom d'utilisateur elle-meme, sans intervention d'un
// administrateur.
func TestUsers_Rectification(t *testing.T) {
	s := newSuite(t)
	u := s.newAccount(t, domain.RoleUser)
	other := s.newAccount(t, domain.RoleUser)

	t.Run("sans jeton : 401", func(t *testing.T) {
		s.do(t, http.MethodPatch, "/users/me", "", map[string]any{"email": "x@y.io", "username": "xyz"}).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")
	})

	t.Run("email invalide : 400", func(t *testing.T) {
		s.do(t, http.MethodPatch, "/users/me", u.Access, map[string]any{"email": "pas-un-email", "username": "valide"}).expect(t, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("email deja pris par un autre compte : 409", func(t *testing.T) {
		s.do(t, http.MethodPatch, "/users/me", u.Access, map[string]any{"email": other.Email, "username": "nouveau"}).expect(t, http.StatusConflict, "CONFLICT")
	})

	t.Run("rectification : PATCH /users/me", func(t *testing.T) {
		d := s.do(t, http.MethodPatch, "/users/me", u.Access, map[string]any{
			"email": "rectifie@streampulse.local", "username": "rectifie",
		}).expect(t, http.StatusOK, "").data(t)
		if str(d, "email") != "rectifie@streampulse.local" || str(d, "username") != "rectifie" {
			t.Fatalf("profil non rectifie: %v", d)
		}

		// La rectification est bien lue en base, pas seulement renvoyee dans
		// la reponse.
		got := s.do(t, http.MethodGet, "/users/me", u.Access, nil).expect(t, http.StatusOK, "").data(t)
		if str(got, "email") != "rectifie@streampulse.local" || str(got, "username") != "rectifie" {
			t.Fatalf("rectification non persistee: %v", got)
		}
	})
}

// UC-21 : l'administrateur traite une demande d'effacement recue hors
// application.
func TestAdmin_DeleteUser(t *testing.T) {
	s := newSuite(t)
	admin := s.newAccount(t, domain.RoleAdmin)
	u := s.newAccount(t, domain.RoleUser)

	t.Run("identifiants invalides", func(t *testing.T) {
		s.do(t, http.MethodDelete, "/admin/users/pas-un-uuid", admin.Access, nil).expect(t, http.StatusBadRequest, "BAD_REQUEST")
		s.do(t, http.MethodDelete, "/admin/users/"+uuid.NewString(), admin.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
	})

	t.Run("un user ne supprime pas un autre compte", func(t *testing.T) {
		s.do(t, http.MethodDelete, "/admin/users/"+admin.ID, u.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")
	})

	t.Run("suppression par l'admin", func(t *testing.T) {
		d := s.do(t, http.MethodDelete, "/admin/users/"+u.ID, admin.Access, nil).expect(t, http.StatusOK, "").data(t)
		if str(d, "status") != "deleted" {
			t.Fatalf("reponse inattendue: %v", d)
		}
		s.do(t, http.MethodGet, "/users/me", u.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodDelete, "/admin/users/"+u.ID, admin.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		r := s.do(t, http.MethodGet, "/admin/users?per_page=100", admin.Access, nil).expect(t, http.StatusOK, "")
		if containsID(r.list(t), u.ID) {
			t.Fatal("le compte supprime apparait encore dans la liste admin")
		}
	})
}
