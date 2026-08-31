package postgres_test

// Tests d'integration des repositories contre une vraie base PostgreSQL.
//
// Ce que les mocks ne peuvent pas prouver, et qui est teste ici : la
// contrainte d'unicite sur l'email, les cascades de suppression, l'expiration
// des refresh tokens calculee en base, la recherche plein texte, et surtout
// le caractere transactionnel du reordonnancement de playlist.
//
// Execution : DATABASE_URL=postgres://... go test ./internal/infrastructure/postgres/
// Sans DATABASE_URL, chaque test est ignore.

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/postgres"
	"github.com/streampulse/backend/testutil"
)

var (
	dbOnce sync.Once
	dbPool *pgxpool.Pool
)

func db(t *testing.T) *pgxpool.Pool {
	t.Helper()
	if os.Getenv("DATABASE_URL") == "" {
		t.Skip("DATABASE_URL non defini : test d'integration ignore")
	}
	dbOnce.Do(func() { dbPool = testutil.OpenTestDB(t, "it_postgres") })
	return dbPool
}

func newUser(t *testing.T, pool *pgxpool.Pool, role domain.Role) *domain.User {
	t.Helper()
	u := testutil.NewTestUser(role)
	if err := postgres.NewUserRepo(pool).Create(context.Background(), u); err != nil {
		t.Fatalf("creation utilisateur: %v", err)
	}
	return u
}

func newStream(t *testing.T, pool *pgxpool.Pool, owner uuid.UUID) *domain.Stream {
	t.Helper()
	s := testutil.NewTestStream(owner)
	if err := postgres.NewStreamRepo(pool).Create(context.Background(), s); err != nil {
		t.Fatalf("creation stream: %v", err)
	}
	return s
}

// --- users -----------------------------------------------------------------

func TestUserRepo_CreateAndFind(t *testing.T) {
	pool := db(t)
	repo := postgres.NewUserRepo(pool)
	ctx := context.Background()

	u := newUser(t, pool, domain.RoleBroadcaster)
	if u.CreatedAt.IsZero() || u.UpdatedAt.IsZero() {
		t.Fatal("Create doit horodater l'utilisateur")
	}

	byEmail, err := repo.FindByEmail(ctx, u.Email)
	if err != nil {
		t.Fatalf("FindByEmail: %v", err)
	}
	byID, err := repo.FindByID(ctx, u.ID)
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if byEmail.ID != u.ID || byID.Email != u.Email || byID.Role != domain.RoleBroadcaster {
		t.Fatalf("lecture incoherente: %+v / %+v", byEmail, byID)
	}
	if byID.PasswordHash != u.PasswordHash {
		t.Fatal("le hash du mot de passe doit etre relu tel quel")
	}

	if _, err := repo.FindByEmail(ctx, "nobody@example.com"); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("email inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if _, err := repo.FindByID(ctx, uuid.New()); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("id inconnu: attendu ErrNotFound, obtenu %v", err)
	}
}

// La contrainte UNIQUE(email) est en base, pas dans le code : seul un vrai
// PostgreSQL peut prouver qu'elle est traduite en ErrAlreadyExists.
func TestUserRepo_DuplicateEmail(t *testing.T) {
	pool := db(t)
	repo := postgres.NewUserRepo(pool)

	first := newUser(t, pool, domain.RoleUser)
	dup := testutil.NewTestUser(domain.RoleUser)
	dup.Email = first.Email

	if err := repo.Create(context.Background(), dup); !errors.Is(err, domain.ErrAlreadyExists) {
		t.Fatalf("attendu ErrAlreadyExists, obtenu %v", err)
	}
}

func TestUserRepo_UpdateRole(t *testing.T) {
	pool := db(t)
	repo := postgres.NewUserRepo(pool)
	ctx := context.Background()
	u := newUser(t, pool, domain.RoleUser)

	if err := repo.UpdateRole(ctx, uuid.New(), domain.RoleAdmin); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("id inconnu: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.UpdateRole(ctx, u.ID, domain.RoleAdmin); err != nil {
		t.Fatalf("UpdateRole: %v", err)
	}
	got, err := repo.FindByID(ctx, u.ID)
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if got.Role != domain.RoleAdmin {
		t.Fatalf("role = %s, attendu admin", got.Role)
	}
	if !got.UpdatedAt.After(u.UpdatedAt) {
		t.Fatal("updated_at doit avancer")
	}
}

func TestUserRepo_ListPaginates(t *testing.T) {
	pool := db(t)
	repo := postgres.NewUserRepo(pool)
	ctx := context.Background()
	for i := 0; i < 3; i++ {
		newUser(t, pool, domain.RoleUser)
	}

	page1, total, err := repo.List(ctx, 1, 2)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if total < 3 || len(page1) != 2 {
		t.Fatalf("total=%d len=%d, attendu total>=3 et 2 elements", total, len(page1))
	}
	page2, _, err := repo.List(ctx, 2, 2)
	if err != nil {
		t.Fatalf("List page 2: %v", err)
	}
	if len(page2) == 0 || page2[0].ID == page1[0].ID {
		t.Fatal("la page 2 doit contenir d'autres lignes que la page 1")
	}
}

// --- refresh tokens ----------------------------------------------------------

func TestRefreshTokenRepo_Lifecycle(t *testing.T) {
	pool := db(t)
	repo := postgres.NewRefreshTokenRepo(pool)
	ctx := context.Background()
	u := newUser(t, pool, domain.RoleUser)

	if err := repo.Store(ctx, u.ID, "hash-1", "pas-une-date"); err == nil {
		t.Fatal("un expiresAt qui n'est pas un time.Time doit etre refuse")
	}
	if err := repo.Store(ctx, u.ID, "hash-1", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("Store: %v", err)
	}

	got, err := repo.FindByHash(ctx, "hash-1")
	if err != nil || got != u.ID {
		t.Fatalf("FindByHash = %s, %v ; attendu %s", got, err, u.ID)
	}
	if _, err := repo.FindByHash(ctx, "hash-inconnu"); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("hash inconnu: attendu ErrNotFound, obtenu %v", err)
	}

	if err := repo.DeleteByUserID(ctx, u.ID); err != nil {
		t.Fatalf("DeleteByUserID: %v", err)
	}
	if _, err := repo.FindByHash(ctx, "hash-1"); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("apres revocation: attendu ErrNotFound, obtenu %v", err)
	}
}

// L'expiration est evaluee a la lecture : un jeton perime encore en base est
// refuse avec ErrTokenExpired, et DeleteExpired le purge.
func TestRefreshTokenRepo_Expired(t *testing.T) {
	pool := db(t)
	repo := postgres.NewRefreshTokenRepo(pool)
	ctx := context.Background()
	u := newUser(t, pool, domain.RoleUser)

	if err := repo.Store(ctx, u.ID, "hash-expire", time.Now().Add(-time.Minute)); err != nil {
		t.Fatalf("Store: %v", err)
	}
	if _, err := repo.FindByHash(ctx, "hash-expire"); !errors.Is(err, domain.ErrTokenExpired) {
		t.Fatalf("attendu ErrTokenExpired, obtenu %v", err)
	}
	if err := repo.DeleteExpired(ctx); err != nil {
		t.Fatalf("DeleteExpired: %v", err)
	}
	if _, err := repo.FindByHash(ctx, "hash-expire"); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("apres purge: attendu ErrNotFound, obtenu %v", err)
	}
}

// Integrite des donnees : supprimer un compte emporte ses jetons et ses flux
// (ON DELETE CASCADE). Aucune reference orpheline ne doit survivre.
func TestCascadeOnUserDelete(t *testing.T) {
	pool := db(t)
	ctx := context.Background()
	users := postgres.NewUserRepo(pool)
	u := newUser(t, pool, domain.RoleBroadcaster)
	s := newStream(t, pool, u.ID)
	tokens := postgres.NewRefreshTokenRepo(pool)
	if err := tokens.Store(ctx, u.ID, "hash-cascade", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("Store: %v", err)
	}
	p := testutil.NewTestPlaylist(u.ID)
	if err := postgres.NewPlaylistRepo(pool).Create(ctx, p); err != nil {
		t.Fatalf("Create playlist: %v", err)
	}
	if err := postgres.NewFavoriteRepo(pool).Add(ctx, u.ID, s.ID); err != nil {
		t.Fatalf("Add favorite: %v", err)
	}

	// Le droit a l'effacement passe par UserRepo.Delete : c'est lui, et non
	// un DELETE ecrit a la main, qui doit declencher les cascades.
	if err := users.Delete(ctx, u.ID); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if err := users.Delete(ctx, u.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("seconde suppression: attendu ErrNotFound, obtenu %v", err)
	}
	if _, err := users.FindByID(ctx, u.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("compte encore present: %v", err)
	}

	if _, err := tokens.FindByHash(ctx, "hash-cascade"); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("jeton orphelin: %v", err)
	}
	if _, err := postgres.NewStreamRepo(pool).FindByID(ctx, s.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("flux orphelin: %v", err)
	}
	if _, err := postgres.NewPlaylistRepo(pool).FindByID(ctx, p.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("playlist orpheline: %v", err)
	}
	var favorites int
	if err := pool.QueryRow(ctx, "SELECT COUNT(*) FROM favorites WHERE user_id = $1", u.ID).Scan(&favorites); err != nil {
		t.Fatalf("comptage favoris: %v", err)
	}
	if favorites != 0 {
		t.Fatalf("%d favori(s) orphelin(s)", favorites)
	}
}

// --- streams -----------------------------------------------------------------

func TestStreamRepo_Lifecycle(t *testing.T) {
	pool := db(t)
	repo := postgres.NewStreamRepo(pool)
	ctx := context.Background()
	owner := newUser(t, pool, domain.RoleBroadcaster)

	s := &domain.Stream{Title: "Live jazz", Description: "d", OwnerID: owner.ID, Format: "mp3", Status: "live"}
	if err := repo.Create(ctx, s); err != nil {
		t.Fatalf("Create: %v", err)
	}
	if s.Status != domain.StreamStatusIdle {
		t.Fatalf("un flux nait idle quel que soit le statut fourni, obtenu %s", s.Status)
	}

	if err := repo.UpdateStatus(ctx, s.ID, domain.StreamStatusLive); err != nil {
		t.Fatalf("UpdateStatus: %v", err)
	}
	if err := repo.UpdateListenerCount(ctx, s.ID, 7); err != nil {
		t.Fatalf("UpdateListenerCount: %v", err)
	}
	s.Title, s.Description = "Live jazz (soir)", "d2"
	if err := repo.Update(ctx, s); err != nil {
		t.Fatalf("Update: %v", err)
	}

	got, err := repo.FindByID(ctx, s.ID)
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if got.Status != domain.StreamStatusLive || got.ListenerCount != 7 || got.Title != "Live jazz (soir)" {
		t.Fatalf("etat relu incoherent: %+v", got)
	}

	list, total, err := repo.List(ctx, 1, 100)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	found := false
	for _, it := range list {
		if it.ID == s.ID {
			found = true
		}
	}
	if !found || total < 1 {
		t.Fatalf("le flux doit apparaitre dans la liste (total=%d)", total)
	}

	if err := repo.Delete(ctx, s.ID); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	for name, err := range map[string]error{
		"Delete":       repo.Delete(ctx, s.ID),
		"UpdateStatus": repo.UpdateStatus(ctx, s.ID, domain.StreamStatusEnded),
		"Update":       repo.Update(ctx, s),
	} {
		if !errors.Is(err, domain.ErrNotFound) {
			t.Errorf("%s apres suppression: attendu ErrNotFound, obtenu %v", name, err)
		}
	}
}

// --- playlists ---------------------------------------------------------------

func addTracks(t *testing.T, repo *postgres.PlaylistRepo, playlistID uuid.UUID, n int) []uuid.UUID {
	t.Helper()
	ids := make([]uuid.UUID, 0, n)
	for i := 0; i < n; i++ {
		tr := &domain.Track{Title: fmt.Sprintf("Piste %d", i), URL: "https://cdn.test/t.mp3", Duration: 60}
		if err := repo.AddTrack(context.Background(), playlistID, tr); err != nil {
			t.Fatalf("AddTrack %d: %v", i, err)
		}
		if tr.Position != i {
			t.Fatalf("piste %d inseree en position %d", i, tr.Position)
		}
		ids = append(ids, tr.ID)
	}
	return ids
}

func positions(t *testing.T, repo *postgres.PlaylistRepo, playlistID uuid.UUID) []uuid.UUID {
	t.Helper()
	p, err := repo.FindByID(context.Background(), playlistID)
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	order := make([]uuid.UUID, 0, len(p.Tracks))
	for i, tr := range p.Tracks {
		if tr.Position != i {
			t.Fatalf("positions non contigues: %+v", p.Tracks)
		}
		order = append(order, tr.ID)
	}
	return order
}

func sameOrder(a, b []uuid.UUID) bool {
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

func TestPlaylistRepo_QueueOrdering(t *testing.T) {
	pool := db(t)
	repo := postgres.NewPlaylistRepo(pool)
	ctx := context.Background()
	owner := newUser(t, pool, domain.RoleUser)

	p := testutil.NewTestPlaylist(owner.ID)
	if err := repo.Create(ctx, p); err != nil {
		t.Fatalf("Create: %v", err)
	}
	ids := addTracks(t, repo, p.ID, 3)

	// Reordonnancement complet : l'ordre inverse est persiste, positions 0..2.
	reversed := []uuid.UUID{ids[2], ids[1], ids[0]}
	if err := repo.ReorderTracks(ctx, p.ID, reversed); err != nil {
		t.Fatalf("ReorderTracks: %v", err)
	}
	if got := positions(t, repo, p.ID); !sameOrder(got, reversed) {
		t.Fatalf("ordre relu %v, attendu %v", got, reversed)
	}

	// Suppression au milieu : les positions se resserrent sans trou.
	if err := repo.RemoveTrack(ctx, p.ID, ids[1]); err != nil {
		t.Fatalf("RemoveTrack: %v", err)
	}
	if got := positions(t, repo, p.ID); !sameOrder(got, []uuid.UUID{ids[2], ids[0]}) {
		t.Fatalf("apres suppression: ordre %v", got)
	}
	if err := repo.RemoveTrack(ctx, p.ID, ids[1]); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("suppression rejouee: attendu ErrNotFound, obtenu %v", err)
	}
}

// Le reordonnancement est transactionnel : une liste incomplete ou un
// identifiant etranger doivent etre refuses SANS laisser la playlist a
// moitie reordonnee. C'est la raison d'etre de la transaction, et un mock ne
// peut pas le prouver.
func TestPlaylistRepo_ReorderIsAtomic(t *testing.T) {
	pool := db(t)
	repo := postgres.NewPlaylistRepo(pool)
	ctx := context.Background()
	owner := newUser(t, pool, domain.RoleUser)

	p := testutil.NewTestPlaylist(owner.ID)
	if err := repo.Create(ctx, p); err != nil {
		t.Fatalf("Create: %v", err)
	}
	ids := addTracks(t, repo, p.ID, 3)

	other := testutil.NewTestPlaylist(owner.ID)
	if err := repo.Create(ctx, other); err != nil {
		t.Fatalf("Create (autre): %v", err)
	}
	foreign := addTracks(t, repo, other.ID, 1)

	t.Run("liste incomplete", func(t *testing.T) {
		err := repo.ReorderTracks(ctx, p.ID, []uuid.UUID{ids[2], ids[0]})
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("attendu ErrInvalidInput, obtenu %v", err)
		}
		if got := positions(t, repo, p.ID); !sameOrder(got, ids) {
			t.Fatalf("la playlist a ete modifiee malgre le refus: %v", got)
		}
	})

	t.Run("piste d'une autre playlist", func(t *testing.T) {
		// ids[2] et ids[1] sont mis a jour avant que foreign[0] echoue :
		// sans transaction, ils resteraient deplaces.
		err := repo.ReorderTracks(ctx, p.ID, []uuid.UUID{ids[2], ids[1], foreign[0]})
		if !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
		if got := positions(t, repo, p.ID); !sameOrder(got, ids) {
			t.Fatalf("rollback non effectue, ordre %v attendu %v", got, ids)
		}
	})
}

func TestPlaylistRepo_ListsAndVisibility(t *testing.T) {
	pool := db(t)
	repo := postgres.NewPlaylistRepo(pool)
	ctx := context.Background()
	owner := newUser(t, pool, domain.RoleUser)

	private := testutil.NewTestPlaylist(owner.ID)
	public := testutil.NewTestPlaylist(owner.ID)
	public.IsPublic = true
	for _, p := range []*domain.Playlist{private, public} {
		if err := repo.Create(ctx, p); err != nil {
			t.Fatalf("Create: %v", err)
		}
	}

	mine, total, err := repo.ListByOwner(ctx, owner.ID, 1, 10)
	if err != nil {
		t.Fatalf("ListByOwner: %v", err)
	}
	if total != 2 || len(mine) != 2 {
		t.Fatalf("ListByOwner total=%d len=%d, attendu 2", total, len(mine))
	}

	pub, _, err := repo.ListPublic(ctx, 1, 100)
	if err != nil {
		t.Fatalf("ListPublic: %v", err)
	}
	for _, p := range pub {
		if p.ID == private.ID {
			t.Fatal("une playlist privee ne doit jamais apparaitre dans ListPublic")
		}
	}

	private.Name, private.IsPublic = "Renommee", true
	if err := repo.Update(ctx, private); err != nil {
		t.Fatalf("Update: %v", err)
	}
	got, err := repo.FindByID(ctx, private.ID)
	if err != nil || got.Name != "Renommee" || !got.IsPublic {
		t.Fatalf("Update non applique: %+v (%v)", got, err)
	}

	if err := repo.Delete(ctx, private.ID); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if err := repo.Delete(ctx, private.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Delete rejoue: attendu ErrNotFound, obtenu %v", err)
	}
}

// --- favoris -----------------------------------------------------------------

func TestFavoriteRepo(t *testing.T) {
	pool := db(t)
	repo := postgres.NewFavoriteRepo(pool)
	ctx := context.Background()
	u := newUser(t, pool, domain.RoleUser)
	s := newStream(t, pool, u.ID)

	// Ajout idempotent : la cle primaire (user, stream) absorbe le doublon.
	for i := 0; i < 2; i++ {
		if err := repo.Add(ctx, u.ID, s.ID); err != nil {
			t.Fatalf("Add %d: %v", i, err)
		}
	}
	exists, err := repo.Exists(ctx, u.ID, s.ID)
	if err != nil || !exists {
		t.Fatalf("Exists = %v, %v", exists, err)
	}
	list, total, err := repo.ListByUser(ctx, u.ID, 1, 10)
	if err != nil {
		t.Fatalf("ListByUser: %v", err)
	}
	if total != 1 || len(list) != 1 || list[0].ID != s.ID {
		t.Fatalf("ListByUser total=%d list=%+v", total, list)
	}

	if err := repo.Add(ctx, u.ID, uuid.New()); err == nil {
		t.Fatal("la cle etrangere doit refuser un flux inexistant")
	}

	if err := repo.Remove(ctx, u.ID, s.ID); err != nil {
		t.Fatalf("Remove: %v", err)
	}
	if err := repo.Remove(ctx, u.ID, s.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Remove rejoue: attendu ErrNotFound, obtenu %v", err)
	}
}

// --- musique -----------------------------------------------------------------

func TestMusicRepo_CRUDAndSearch(t *testing.T) {
	pool := db(t)
	repo := postgres.NewMusicRepo(pool)
	ctx := context.Background()
	uploader := newUser(t, pool, domain.RoleBroadcaster)

	m := &domain.Music{Title: "Nocturne in E-flat", Artist: "Frederic Chopin", Album: "Op. 9", Duration: 270,
		URL: "https://cdn.test/nocturne.mp3", UploadedBy: uploader.ID}
	if err := repo.Create(ctx, m); err != nil {
		t.Fatalf("Create: %v", err)
	}

	got, err := repo.FindByID(ctx, m.ID)
	if err != nil {
		t.Fatalf("FindByID: %v", err)
	}
	if got.CoverURL != "" {
		t.Fatalf("cover_url NULL doit se lire comme chaine vide, obtenu %q", got.CoverURL)
	}

	// Recherche plein texte PostgreSQL : le stemming anglais rapproche
	// "nocturnes" de "nocturne", et la casse est ignoree.
	for _, q := range []string{"chopin", "Nocturnes", "frederic nocturne"} {
		found, total, err := repo.Search(ctx, q, 1, 10)
		if err != nil {
			t.Fatalf("Search %q: %v", q, err)
		}
		hit := false
		for _, it := range found {
			if it.ID == m.ID {
				hit = true
			}
		}
		if !hit || total < 1 {
			t.Errorf("Search %q ne trouve pas le morceau (total=%d)", q, total)
		}
	}
	if _, total, _ := repo.Search(ctx, "zzzz-inexistant", 1, 10); total != 0 {
		t.Errorf("recherche sans correspondance: total=%d", total)
	}

	mine, total, err := repo.ListByUploader(ctx, uploader.ID, 1, 10)
	if err != nil || total != 1 || len(mine) != 1 {
		t.Fatalf("ListByUploader: total=%d len=%d err=%v", total, len(mine), err)
	}

	m.CoverURL = "https://cdn.test/cover.jpg"
	m.Title = "Nocturne Op. 9 No. 2"
	if err := repo.Update(ctx, m); err != nil {
		t.Fatalf("Update: %v", err)
	}
	got, _ = repo.FindByID(ctx, m.ID)
	if got.Title != m.Title || got.CoverURL != m.CoverURL {
		t.Fatalf("Update non applique: %+v", got)
	}

	if err := repo.Delete(ctx, m.ID); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := repo.FindByID(ctx, m.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("apres Delete: attendu ErrNotFound, obtenu %v", err)
	}
	if err := repo.Update(ctx, m); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Update d'un supprime: attendu ErrNotFound, obtenu %v", err)
	}
}

func TestMusicFavoriteRepo(t *testing.T) {
	pool := db(t)
	repo := postgres.NewMusicFavoriteRepo(pool)
	ctx := context.Background()
	u := newUser(t, pool, domain.RoleUser)
	m := &domain.Music{Title: "T", URL: "https://cdn.test/t.mp3", UploadedBy: u.ID}
	if err := postgres.NewMusicRepo(pool).Create(ctx, m); err != nil {
		t.Fatalf("Create music: %v", err)
	}

	if err := repo.Add(ctx, u.ID, m.ID); err != nil {
		t.Fatalf("Add: %v", err)
	}
	ids, err := repo.ListIDs(ctx, u.ID)
	if err != nil || len(ids) != 1 || ids[0] != m.ID {
		t.Fatalf("ListIDs = %v, %v", ids, err)
	}
	list, total, err := repo.ListByUser(ctx, u.ID, 1, 10)
	if err != nil || total != 1 || len(list) != 1 || list[0].ID != m.ID {
		t.Fatalf("ListByUser total=%d list=%+v err=%v", total, list, err)
	}
	exists, err := repo.Exists(ctx, u.ID, m.ID)
	if err != nil || !exists {
		t.Fatalf("Exists = %v, %v", exists, err)
	}
	if err := repo.Remove(ctx, u.ID, m.ID); err != nil {
		t.Fatalf("Remove: %v", err)
	}
	if err := repo.Remove(ctx, u.ID, m.ID); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("Remove rejoue: attendu ErrNotFound, obtenu %v", err)
	}
}

// --- migrations --------------------------------------------------------------

// Rejouer les migrations sur une base a jour ne doit rien faire : c'est ce
// qui rend le demarrage du serveur idempotent.
func TestRunMigrations_Idempotent(t *testing.T) {
	pool := db(t)
	ctx := context.Background()

	var before int
	if err := pool.QueryRow(ctx, "SELECT COUNT(*) FROM schema_migrations").Scan(&before); err != nil {
		t.Fatalf("count: %v", err)
	}
	if before == 0 {
		t.Fatal("aucune migration enregistree apres OpenTestDB")
	}
	if err := postgres.RunMigrations(ctx, pool, zerolog.Nop()); err != nil {
		t.Fatalf("RunMigrations rejoue: %v", err)
	}
	var after int
	if err := pool.QueryRow(ctx, "SELECT COUNT(*) FROM schema_migrations").Scan(&after); err != nil {
		t.Fatalf("count: %v", err)
	}
	if after != before {
		t.Fatalf("migrations rejouees: %d -> %d", before, after)
	}
}
