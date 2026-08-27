package testutil

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog"

	"github.com/streampulse/backend/internal/infrastructure/postgres"
)

// OpenTestDB ouvre un pool vers la base designee par DATABASE_URL, dans un
// schema PostgreSQL dedie au paquet appelant, vide et migre.
//
// Pourquoi un schema par paquet : `go test ./...` execute les paquets en
// parallele. Deux suites qui partageraient les tables `users` ou `streams`
// se marcheraient dessus (comptes en double, totaux faux). Avec
// `search_path = <schema>,public`, chaque suite a ses propres tables et
// part d'un etat connu : le schema est detruit et recree a chaque ouverture.
//
// Sans DATABASE_URL, le test est ignore (t.Skip) : la suite unitaire reste
// jouable sans base, la suite d'integration en exige une. La CI en fournit
// une (service postgres de .github/workflows/backend.yml).
//
// Le pool n'est pas ferme : il est partage par tous les tests du paquet et
// vit aussi longtemps que le binaire de test.
func OpenTestDB(t testing.TB, schema string) *pgxpool.Pool {
	t.Helper()

	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL non defini : test d'integration ignore")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Preparation via une connexion sans search_path particulier.
	// L'extension est installee une fois pour toutes dans `public` : si la
	// migration 001 la creait dans le schema du paquet, le DROP SCHEMA d'un
	// autre paquet l'emporterait en cascade, avec les colonnes qui en
	// dependent.
	admin, err := postgres.NewPool(ctx, dsn)
	if err != nil {
		t.Fatalf("connexion a DATABASE_URL: %v", err)
	}
	defer admin.Close()
	for _, stmt := range []string{
		`CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public`,
		fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema),
		fmt.Sprintf("CREATE SCHEMA %s", schema),
	} {
		if _, err := admin.Exec(ctx, stmt); err != nil {
			t.Fatalf("preparation du schema %s: %v", schema, err)
		}
	}

	pool, err := postgres.NewPool(ctx, withSearchPath(t, dsn, schema))
	if err != nil {
		t.Fatalf("connexion au schema %s: %v", schema, err)
	}
	if err := postgres.RunMigrations(ctx, pool, zerolog.Nop()); err != nil {
		t.Fatalf("migrations dans %s: %v", schema, err)
	}
	return pool
}

// withSearchPath ajoute search_path=<schema>,public a l'URL : pgx transmet
// les parametres d'URL qu'il ne connait pas comme parametres de session
// PostgreSQL.
func withSearchPath(t testing.TB, dsn, schema string) string {
	t.Helper()
	u, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("DATABASE_URL invalide: %v", err)
	}
	q := u.Query()
	q.Set("search_path", schema+",public")
	u.RawQuery = q.Encode()
	return u.String()
}
