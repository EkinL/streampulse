package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/transport/http/dto"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

type FeedbackHandler struct {
	feedbackService *application.FeedbackService
}

func NewFeedbackHandler(feedbackService *application.FeedbackService) *FeedbackHandler {
	return &FeedbackHandler{feedbackService: feedbackService}
}

// Submit signale un bug ou une suggestion : le canal de retour utilisateur
// ouvert a tout compte authentifie, quel que soit son role.
func (h *FeedbackHandler) Submit(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	var req dto.SubmitFeedbackRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	userID, _ := uuid.Parse(claims.UserID)
	feedback, err := h.feedbackService.Submit(r.Context(), application.SubmitFeedbackInput{
		UserID:     userID,
		Type:       domain.FeedbackType(req.Type),
		Message:    req.Message,
		AppVersion: req.AppVersion,
		Platform:   req.Platform,
	})
	if err != nil {
		if errors.Is(err, domain.ErrInvalidInput) {
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to submit feedback")
		return
	}

	respondJSON(w, http.StatusCreated, toFeedbackResponse(feedback))
}

// ListFeedback rend les signalements, plus recents d'abord, optionnellement
// filtres par `?status=`. Reserve a l'administration.
func (h *FeedbackHandler) ListFeedback(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = 20
	}

	status := domain.FeedbackStatus(r.URL.Query().Get("status"))
	items, total, err := h.feedbackService.List(r.Context(), status, page, perPage)
	if err != nil {
		if errors.Is(err, domain.ErrInvalidInput) {
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list feedback")
		return
	}

	responses := make([]dto.FeedbackResponse, 0, len(items))
	for _, f := range items {
		responses = append(responses, toFeedbackResponse(&f))
	}
	respondPaginated(w, responses, page, perPage, total)
}

// UpdateFeedbackStatus fait avancer un signalement dans son cycle de
// traitement (new -> in_progress -> resolved). Reserve a l'administration.
func (h *FeedbackHandler) UpdateFeedbackStatus(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid feedback id")
		return
	}

	var req dto.UpdateFeedbackStatusRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	if err := h.feedbackService.UpdateStatus(r.Context(), id, domain.FeedbackStatus(req.Status)); err != nil {
		if errors.Is(err, domain.ErrInvalidInput) {
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "feedback not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update feedback status")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func toFeedbackResponse(f *domain.Feedback) dto.FeedbackResponse {
	return dto.FeedbackResponse{
		ID:         f.ID.String(),
		UserID:     f.UserID.String(),
		Type:       string(f.Type),
		Message:    f.Message,
		AppVersion: f.AppVersion,
		Platform:   f.Platform,
		Status:     string(f.Status),
		CreatedAt:  f.CreatedAt,
		UpdatedAt:  f.UpdatedAt,
	}
}
