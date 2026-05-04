package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/transport/http/dto"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

type FavoritesHandler struct {
	favoriteRepo domain.FavoriteRepository
	streamRepo   domain.StreamRepository
}

func NewFavoritesHandler(favoriteRepo domain.FavoriteRepository, streamRepo domain.StreamRepository) *FavoritesHandler {
	return &FavoritesHandler{favoriteRepo: favoriteRepo, streamRepo: streamRepo}
}

func (h *FavoritesHandler) ListFavorites(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = 20
	}

	userID, _ := uuid.Parse(claims.UserID)
	streams, total, err := h.favoriteRepo.ListByUser(r.Context(), userID, page, perPage)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list favorites")
		return
	}

	items := make([]dto.StreamResponse, 0, len(streams))
	for _, s := range streams {
		items = append(items, dto.StreamResponse{
			ID:            s.ID.String(),
			Title:         s.Title,
			Description:   s.Description,
			OwnerID:       s.OwnerID.String(),
			Status:        string(s.Status),
			ListenerCount: s.ListenerCount,
			Format:        s.Format,
			CreatedAt:     s.CreatedAt,
			UpdatedAt:     s.UpdatedAt,
		})
	}
	respondPaginated(w, items, page, perPage, total)
}

func (h *FavoritesHandler) AddFavorite(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	streamID, err := uuid.Parse(chi.URLParam(r, "streamId"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid stream id")
		return
	}

	// Verify stream exists
	if _, err := h.streamRepo.FindByID(r.Context(), streamID); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "stream not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check stream")
		return
	}

	userID, _ := uuid.Parse(claims.UserID)
	if err := h.favoriteRepo.Add(r.Context(), userID, streamID); err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to add favorite")
		return
	}

	respondJSON(w, http.StatusCreated, map[string]string{"status": "added"})
}

func (h *FavoritesHandler) RemoveFavorite(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	streamID, err := uuid.Parse(chi.URLParam(r, "streamId"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid stream id")
		return
	}

	userID, _ := uuid.Parse(claims.UserID)
	if err := h.favoriteRepo.Remove(r.Context(), userID, streamID); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "favorite not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to remove favorite")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "removed"})
}
