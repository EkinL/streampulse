package middleware

import (
	"net/http"

	chimiddleware "github.com/go-chi/chi/v5/middleware"
)

// RequestIDHeaderName est le nom du header porteur de l'identifiant de requete.
const RequestIDHeaderName = "X-Request-Id"

// RequestIDHeader recopie l'identifiant genere par chimiddleware.RequestID dans
// un header de reponse.
//
// chi ne place cet identifiant que dans le contexte : il n'atteint jamais le
// client. Le poser en header a deux effets.
//
// D'abord, il devient lisible par les helpers de reponse sans imposer un
// parametre *http.Request aux 191 appels de respondJSON / respondError /
// respondPaginated.
//
// Ensuite, et surtout, il accompagne AUSSI les reponses ecrites par
// http.Error dans la chaine de middlewares (401, 403, 429), qui n'ont pas
// d'enveloppe meta et n'avaient donc jusqu'ici aucun identifiant exploitable.
//
// A enregistrer immediatement apres chimiddleware.RequestID, et avant tout
// middleware susceptible d'ecrire une reponse : un header pose apres
// WriteHeader est ignore.
func RequestIDHeader(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if reqID := chimiddleware.GetReqID(r.Context()); reqID != "" {
			w.Header().Set(RequestIDHeaderName, reqID)
		}
		next.ServeHTTP(w, r)
	})
}
