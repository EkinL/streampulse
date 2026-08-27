package handlers

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/rs/zerolog"
)

// uploadReadTimeout borne la lecture d'un upload multipart (32 Mo max).
// Le ReadTimeout global est prevu pour des requetes JSON, pas pour un
// fichier envoye depuis un mobile en 4G.
const uploadReadTimeout = 2 * time.Minute

// keepConnectionOpen leve les deadlines posees par http.Server (ReadTimeout /
// WriteTimeout) sur la connexion courante. A n'appeler que dans les handlers
// qui gardent volontairement la connexion ouverte sans limite de duree :
// SSE, flux audio brut et broadcast. Toutes les autres routes conservent
// les timeouts globaux, voir docs/ADR/005-http-timeouts.md.
//
// Un echec n'est pas bloquant : le flux fonctionne quand meme, il sera
// simplement coupe par le serveur au bout de WriteTimeout. On le logue pour
// ne pas chercher pendant des heures pourquoi les auditeurs decrochent tous
// a la meme seconde.
func keepConnectionOpen(w http.ResponseWriter, logger zerolog.Logger) {
	if err := clearDeadlines(w); err != nil {
		logger.Warn().Err(err).Msg("cannot clear connection deadlines, stream will be cut by server timeout")
	}
}

// extendDeadlines repousse les deadlines de lecture et d'ecriture de la
// connexion courante a maintenant + d. Les deux : WriteTimeout court depuis
// la fin de la lecture des headers, donc un upload long verrait sa reponse
// 201 partir apres expiration si on ne touchait qu'a la lecture.
func extendDeadlines(w http.ResponseWriter, d time.Duration) error {
	return setDeadlines(w, time.Now().Add(d))
}

// unblockReadOnCancel fait echouer la lecture en cours de r.Body des que ctx
// est annule. Necessaire pour Broadcast : en HTTP/1.1 un Read bloque sur la
// socket ne regarde pas le contexte de la requete, un diffuseur silencieux
// tiendrait la connexion ouverte pendant tout le delai de Shutdown.
// Le stop retourne doit etre appele a la sortie du handler.
func unblockReadOnCancel(ctx context.Context, w http.ResponseWriter) (stop func()) {
	rc := http.NewResponseController(w)
	stopAfterFunc := context.AfterFunc(ctx, func() {
		_ = rc.SetReadDeadline(time.Now())
	})
	return func() { stopAfterFunc() }
}

func clearDeadlines(w http.ResponseWriter) error {
	// time.Time{} = pas de deadline.
	return setDeadlines(w, time.Time{})
}

func setDeadlines(w http.ResponseWriter, t time.Time) error {
	rc := http.NewResponseController(w)

	// httptest.ResponseRecorder par exemple ne supporte pas les deadlines :
	// rien a faire, ce n'est pas une erreur.
	if err := rc.SetReadDeadline(t); err != nil && !errors.Is(err, http.ErrNotSupported) {
		return err
	}
	if err := rc.SetWriteDeadline(t); err != nil && !errors.Is(err, http.ErrNotSupported) {
		return err
	}
	return nil
}
