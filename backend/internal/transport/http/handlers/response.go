package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
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

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	resp := SuccessResponse{
		Data: data,
		Meta: Meta{
			RequestID: uuid.New().String(),
			Timestamp: time.Now().UTC(),
		},
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func respondPaginated(w http.ResponseWriter, data interface{}, page, perPage, total int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	resp := SuccessResponse{
		Data: data,
		Meta: Meta{
			RequestID: uuid.New().String(),
			Timestamp: time.Now().UTC(),
			Page:      page,
			PerPage:   perPage,
			Total:     total,
		},
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
		Meta: Meta{
			RequestID: uuid.New().String(),
			Timestamp: time.Now().UTC(),
		},
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func decodeJSON(r *http.Request, v interface{}) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(v)
}
