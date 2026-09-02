package domain_test

import (
	"testing"

	"github.com/streampulse/backend/internal/domain"
)

func TestStreamStatusIsValid(t *testing.T) {
	valid := []domain.StreamStatus{
		domain.StreamStatusIdle,
		domain.StreamStatusLive,
		domain.StreamStatusEnded,
	}
	for _, s := range valid {
		if !s.IsValid() {
			t.Errorf("statut %q attendu valide", s)
		}
	}
	if domain.StreamStatus("paused").IsValid() {
		t.Error("statut inconnu accepte")
	}
}

func TestRoleIsValid(t *testing.T) {
	valid := []domain.Role{
		domain.RoleAnonymous,
		domain.RoleUser,
		domain.RoleBroadcaster,
		domain.RoleAdmin,
	}
	for _, r := range valid {
		if !r.IsValid() {
			t.Errorf("role %q attendu valide", r)
		}
	}
	// Le sujet ne connait pas de role "listener" : il doit etre refuse.
	if domain.Role("listener").IsValid() {
		t.Error("role inconnu accepte")
	}
}

func TestRoleAtLeast(t *testing.T) {
	cases := []struct {
		role, min domain.Role
		want      bool
	}{
		{domain.RoleAdmin, domain.RoleBroadcaster, true},
		{domain.RoleBroadcaster, domain.RoleBroadcaster, true},
		{domain.RoleUser, domain.RoleBroadcaster, false},
		{domain.RoleAnonymous, domain.RoleUser, false},
		// Un role inconnu est sous tout le monde, meme anonymous.
		{domain.Role("listener"), domain.RoleAnonymous, false},
	}
	for _, c := range cases {
		if got := c.role.AtLeast(c.min); got != c.want {
			t.Errorf("%q.AtLeast(%q) = %v, attendu %v", c.role, c.min, got, c.want)
		}
	}
}
