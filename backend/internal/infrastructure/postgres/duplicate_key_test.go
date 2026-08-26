package postgres

import (
	"errors"
	"fmt"
	"testing"

	"github.com/jackc/pgx/v5"
)

func TestIsDuplicateKeyError(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"no rows", pgx.ErrNoRows, false},
		{"no rows enveloppe", fmt.Errorf("scan: %w", pgx.ErrNoRows), false},
		{"contrainte unique pg", errors.New(`duplicate key value violates unique constraint "users_email_key"`), true},
		{"code sqlstate", errors.New("ERROR: conflit (SQLSTATE 23505)"), true},
		{"autre erreur", errors.New("connection refused"), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isDuplicateKeyError(tc.err); got != tc.want {
				t.Fatalf("isDuplicateKeyError(%v) = %v, attendu %v", tc.err, got, tc.want)
			}
		})
	}
}
