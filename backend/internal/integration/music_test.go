package integration_test

import (
	"bytes"
	"mime/multipart"
	"net/http"
	"os"
	"path"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
)

// UC-11 : catalogue musical par URL, recherche, propriete.
func TestMusic_CatalogueByURL(t *testing.T) {
	s := newSuite(t)
	owner := s.newAccount(t, domain.RoleBroadcaster)
	other := s.newAccount(t, domain.RoleBroadcaster)

	d := s.do(t, http.MethodPost, "/music", owner.Access, map[string]any{
		"title": "Nocturne Op. 9 No. 2", "artist": "Frederic Chopin", "album": "Nocturnes",
		"duration": 270, "url": "https://cdn.test/nocturne.mp3",
	}).expect(t, http.StatusCreated, "").data(t)
	id := str(d, "id")
	if str(d, "uploaded_by") != owner.ID || str(d, "url") != "https://cdn.test/nocturne.mp3" {
		t.Fatalf("morceau cree inattendu: %v", d)
	}

	t.Run("validation", func(t *testing.T) {
		s.do(t, http.MethodPost, "/music", owner.Access, map[string]any{"url": "https://cdn.test/x.mp3"}).expect(t, http.StatusBadRequest, "INVALID_INPUT")
		s.do(t, http.MethodPost, "/music", owner.Access, map[string]any{"title": "Sans URL"}).expect(t, http.StatusBadRequest, "INVALID_INPUT")
		s.do(t, http.MethodPost, "/music", owner.Access, map[string]any{"title": "x", "url": "u", "uploaded_by": other.ID}).expect(t, http.StatusBadRequest, "INVALID_BODY")
	})

	t.Run("lecture et recherche", func(t *testing.T) {
		if got := s.do(t, http.MethodGet, "/music/"+id, "", nil).expect(t, http.StatusOK, "").data(t); str(got, "title") != "Nocturne Op. 9 No. 2" {
			t.Fatalf("lecture: %v", got)
		}
		s.do(t, http.MethodGet, "/music/"+uuid.NewString(), "", nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodGet, "/music/pas-un-uuid", "", nil).expect(t, http.StatusBadRequest, "INVALID_ID")

		if r := s.do(t, http.MethodGet, "/music/search?q=chopin", "", nil).expect(t, http.StatusOK, ""); !containsID(r.list(t), id) {
			t.Fatalf("la recherche plein texte doit trouver le morceau: %s", r.Raw)
		}
		s.do(t, http.MethodGet, "/music/search", "", nil).expect(t, http.StatusBadRequest, "INVALID_INPUT")

		global := s.do(t, http.MethodGet, "/search?q=chopin", "", nil).expect(t, http.StatusOK, "").data(t)
		music, _ := global["music"].([]any)
		if !containsID(music, id) {
			t.Fatalf("la recherche globale doit trouver le morceau: %v", global)
		}
		if _, isList := global["streams"].([]any); !isList {
			t.Fatalf("streams doit etre un tableau (jamais null) : %v", global)
		}
		s.do(t, http.MethodGet, "/search", "", nil).expect(t, http.StatusBadRequest, "INVALID_INPUT")
	})

	t.Run("propriete", func(t *testing.T) {
		update := map[string]any{"title": "Nocturne", "artist": "Chopin", "album": "", "cover_url": "https://cdn.test/cover.jpg"}
		s.do(t, http.MethodPut, "/music/"+id, other.Access, update).expect(t, http.StatusForbidden, "FORBIDDEN")
		s.do(t, http.MethodDelete, "/music/"+id, other.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")

		got := s.do(t, http.MethodPut, "/music/"+id, owner.Access, update).expect(t, http.StatusOK, "").data(t)
		if str(got, "title") != "Nocturne" || str(got, "cover_url") != "https://cdn.test/cover.jpg" {
			t.Fatalf("mise a jour non appliquee: %v", got)
		}
		s.do(t, http.MethodPut, "/music/"+uuid.NewString(), owner.Access, update).expect(t, http.StatusNotFound, "NOT_FOUND")

		// Ce morceau n'a jamais ete ecrit sur disque (ajoute par URL externe) :
		// sa suppression ne doit rien tenter de retirer dans uploads/.
		before := uploadedFiles(t)
		s.do(t, http.MethodDelete, "/music/"+id, owner.Access, nil).expect(t, http.StatusOK, "")
		s.do(t, http.MethodGet, "/music/"+id, "", nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		s.do(t, http.MethodDelete, "/music/"+id, owner.Access, nil).expect(t, http.StatusNotFound, "NOT_FOUND")
		if uploadedFiles(t) != before {
			t.Fatal("la suppression d'un morceau ajoute par URL ne doit pas toucher au disque")
		}
	})
}

func multipartBody(t *testing.T, fields map[string]string, filename string, content []byte) (*bytes.Buffer, string) {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	for k, v := range fields {
		if err := w.WriteField(k, v); err != nil {
			t.Fatalf("champ %s: %v", k, err)
		}
	}
	if filename != "" {
		part, err := w.CreateFormFile("file", filename)
		if err != nil {
			t.Fatalf("partie fichier: %v", err)
		}
		if _, err := part.Write(content); err != nil {
			t.Fatalf("ecriture fichier: %v", err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatalf("fermeture multipart: %v", err)
	}
	return &buf, w.FormDataContentType()
}

func (s *suite) upload(t *testing.T, token string, fields map[string]string, filename string, content []byte) response {
	t.Helper()
	body, contentType := multipartBody(t, fields, filename, content)
	req, err := http.NewRequest(http.MethodPost, s.srv.URL+"/music", body)
	if err != nil {
		t.Fatalf("requete upload: %v", err)
	}
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := s.client.Do(req)
	if err != nil {
		t.Fatalf("upload: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	var raw bytes.Buffer
	if _, err := raw.ReadFrom(resp.Body); err != nil {
		t.Fatalf("lecture upload: %v", err)
	}
	return response{Status: resp.StatusCode, Header: resp.Header, Raw: raw.Bytes()}
}

func uploadedFiles(t *testing.T) int {
	t.Helper()
	entries, err := os.ReadDir(uploadDir)
	if err != nil {
		t.Fatalf("lecture du dossier d'upload: %v", err)
	}
	return len(entries)
}

// UC-11 : upload d'une source audio par fichier (multipart).
func TestMusic_UploadFile(t *testing.T) {
	s := newSuite(t)
	bc := s.newAccount(t, domain.RoleBroadcaster)
	audio := []byte("ID3\x03\x00fake-mp3-bytes")

	before := uploadedFiles(t)
	d := s.upload(t, bc.Access, map[string]string{"title": "Prise 1", "artist": "Studio", "duration": "42"}, "prise-1.mp3", audio).
		expect(t, http.StatusCreated, "").data(t)
	url := str(d, "url")
	if !strings.HasPrefix(url, uploadsBaseURL+"/") || !strings.HasSuffix(url, ".mp3") {
		t.Fatalf("URL publique inattendue: %s", url)
	}
	if dur, _ := d["duration"].(float64); dur != 42 {
		t.Fatalf("duration = %v, attendu 42", d["duration"])
	}
	stored, err := os.ReadFile(path.Join(uploadDir, path.Base(url)))
	if err != nil {
		t.Fatalf("le fichier doit exister sur disque: %v", err)
	}
	if !bytes.Equal(stored, audio) {
		t.Fatal("contenu stocke different du contenu envoye")
	}
	if uploadedFiles(t) != before+1 {
		t.Fatal("exactement un fichier doit avoir ete ecrit")
	}

	// Un upload refuse ne laisse rien sur disque.
	s.upload(t, bc.Access, map[string]string{"title": "Sans fichier"}, "", nil).expect(t, http.StatusBadRequest, "INVALID_BODY")
	s.upload(t, bc.Access, map[string]string{"artist": "Sans titre"}, "x.mp3", audio).expect(t, http.StatusBadRequest, "INVALID_INPUT")
	if uploadedFiles(t) != before+1 {
		t.Fatal("un upload refuse a laisse un fichier sur disque")
	}

	// UC-11 (suite) : DELETE /music/{id} ne doit pas seulement effacer la
	// ligne en base, mais aussi le fichier verse (limite connue, docs/rgpd.md).
	t.Run("suppression retire le fichier du disque", func(t *testing.T) {
		id := str(d, "id")
		s.do(t, http.MethodDelete, "/music/"+id, bc.Access, nil).expect(t, http.StatusOK, "")
		if uploadedFiles(t) != before {
			t.Fatal("le fichier uploade doit avoir disparu du disque apres suppression")
		}
	})
}
