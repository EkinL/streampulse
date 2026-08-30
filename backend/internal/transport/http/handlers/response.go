package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

type Meta struct {
	RequestID string    `json:"requestId"`
	Timestamp time.Time `json:"timestamp"`
	Page      int       `json:"page,omitempty"`
	PerPage   int       `json:"perPage,omitempty"`
	Total     int       `json:"total,omitempty"`
}

type SuccessResponse struct {
	Data interface{} `json:"data"`
	Meta Meta        `json:"meta"`
}

type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type ErrorResponse struct {
	Error ErrorBody `json:"error"`
	Meta  Meta      `json:"meta"`
}

// newMeta construit l'enveloppe meta d'une reponse.
//
// requestId reprend l'identifiant pose en header par middleware.RequestIDHeader,
// et non un uuid neuf : c'est ce qui rend l'identifiant renvoye au client
// retrouvable dans les logs et dans la trace. Le repli sur un uuid genere
// couvre les appels directs a un handler, hors chaine de middlewares (tests
// unitaires), ou le champ ne doit pas etre vide.
func newMeta(w http.ResponseWriter) Meta {
	requestID := w.Header().Get(middleware.RequestIDHeaderName)
	if requestID == "" {
		requestID = uuid.New().String()
	}
	return Meta{
		RequestID: requestID,
		Timestamp: time.Now().UTC(),
	}
}

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	resp := SuccessResponse{
		Data: data,
		Meta: newMeta(w),
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func respondPaginated(w http.ResponseWriter, data interface{}, page, perPage, total int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	meta := newMeta(w)
	meta.Page = page
	meta.PerPage = perPage
	meta.Total = total

	resp := SuccessResponse{
		Data: data,
		Meta: meta,
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func respondError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	resp := ErrorResponse{
		Error: ErrorBody{
			Code:    code,
			Message: message,
		},
		Meta: newMeta(w),
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func decodeJSON(r *http.Request, v interface{}) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(v)
}
