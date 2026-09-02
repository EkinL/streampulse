package integration_test

import (
	"net/http"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
)

// UC-23 : canal de retour utilisateur.
func TestFeedback_SubmitAndAdminWorkflow(t *testing.T) {
	s := newSuite(t)
	u := s.newAccount(t, domain.RoleUser)
	admin := s.newAccount(t, domain.RoleAdmin)

	r := s.do(t, http.MethodPost, "/feedback", u.Access, map[string]any{
		"type": "bug", "message": "Le lecteur coupe le son au bout de 30 secondes.",
		"app_version": "1.0.0", "platform": "android",
	}).expect(t, http.StatusCreated, "")
	d := r.data(t)
	if str(d, "status") != "new" || str(d, "user_id") != u.ID {
		t.Fatalf("signalement mal initialise: %s", r.Raw)
	}
	feedbackID := str(d, "id")

	// Un compte simple ne consulte pas les signalements des autres.
	s.do(t, http.MethodGet, "/admin/feedback", u.Access, nil).expect(t, http.StatusForbidden, "")

	list := s.do(t, http.MethodGet, "/admin/feedback?status=new", admin.Access, nil).expect(t, http.StatusOK, "")
	if !containsID(list.list(t), feedbackID) {
		t.Fatalf("le signalement doit apparaitre pour l'admin: %s", list.Raw)
	}

	s.do(t, http.MethodPut, "/admin/feedback/"+feedbackID+"/status", u.Access, map[string]any{"status": "resolved"}).
		expect(t, http.StatusForbidden, "")

	s.do(t, http.MethodPut, "/admin/feedback/"+feedbackID+"/status", admin.Access, map[string]any{"status": "resolved"}).
		expect(t, http.StatusOK, "")

	resolved := s.do(t, http.MethodGet, "/admin/feedback?status=resolved", admin.Access, nil).expect(t, http.StatusOK, "")
	if !containsID(resolved.list(t), feedbackID) {
		t.Fatalf("le signalement doit apparaitre comme resolu: %s", resolved.Raw)
	}
	stillNew := s.do(t, http.MethodGet, "/admin/feedback?status=new", admin.Access, nil).expect(t, http.StatusOK, "")
	if containsID(stillNew.list(t), feedbackID) {
		t.Fatalf("le signalement ne doit plus apparaitre comme nouveau: %s", stillNew.Raw)
	}
}

func TestFeedback_Validation(t *testing.T) {
	s := newSuite(t)
	u := s.newAccount(t, domain.RoleUser)
	admin := s.newAccount(t, domain.RoleAdmin)

	s.do(t, http.MethodPost, "/feedback", u.Access, map[string]any{"type": "bug", "message": ""}).
		expect(t, http.StatusBadRequest, "BAD_REQUEST")
	s.do(t, http.MethodPost, "/feedback", u.Access, map[string]any{"type": "pas-un-type", "message": "un message"}).
		expect(t, http.StatusBadRequest, "BAD_REQUEST")
	s.do(t, http.MethodPost, "/feedback", "", map[string]any{"type": "bug", "message": "un message"}).
		expect(t, http.StatusUnauthorized, "")

	s.do(t, http.MethodPut, "/admin/feedback/"+uuid.NewString()+"/status", admin.Access, map[string]any{"status": "resolved"}).
		expect(t, http.StatusNotFound, "NOT_FOUND")
	s.do(t, http.MethodPut, "/admin/feedback/pas-un-uuid/status", admin.Access, map[string]any{"status": "resolved"}).
		expect(t, http.StatusBadRequest, "BAD_REQUEST")
}
