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

type MusicFavoritesHandler struct {
	musicFavoriteRepo domain.MusicFavoriteRepository
	musicRepo         domain.MusicRepository
}

func NewMusicFavoritesHandler(musicFavoriteRepo domain.MusicFavoriteRepository, musicRepo domain.MusicRepository) *MusicFavoritesHandler {
	return &MusicFavoritesHandler{musicFavoriteRepo: musicFavoriteRepo, musicRepo: musicRepo}
}

func (h *MusicFavoritesHandler) ListFavorites(w http.ResponseWriter, r *http.Request) {
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
	tracks, total, err := h.musicFavoriteRepo.ListByUser(r.Context(), userID, page, perPage)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list music favorites")
		return
	}

	items := make([]dto.MusicResponse, 0, len(tracks))
	for _, m := range tracks {
		items = append(items, toMusicResponse(&m))
	}
	respondPaginated(w, items, page, perPage, total)
}

func (h *MusicFavoritesHandler) ListFavoriteIDs(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	userID, _ := uuid.Parse(claims.UserID)
	ids, err := h.musicFavoriteRepo.ListIDs(r.Context(), userID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list music favorite ids")
		return
	}

	// Convert to string slice for JSON
	idStrings := make([]string, 0, len(ids))
	for _, id := range ids {
		idStrings = append(idStrings, id.String())
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"ids": idStrings,
	})
}

func (h *MusicFavoritesHandler) AddFavorite(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	musicID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid music id")
		return
	}

	// Verify music exists
	if _, err := h.musicRepo.FindByID(r.Context(), musicID); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "music not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check music")
		return
	}

	userID, _ := uuid.Parse(claims.UserID)
	if err := h.musicFavoriteRepo.Add(r.Context(), userID, musicID); err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to add music favorite")
		return
	}

	respondJSON(w, http.StatusCreated, map[string]string{"status": "added"})
}

func (h *MusicFavoritesHandler) RemoveFavorite(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	musicID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid music id")
		return
	}

	userID, _ := uuid.Parse(claims.UserID)
	if err := h.musicFavoriteRepo.Remove(r.Context(), userID, musicID); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "music favorite not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to remove music favorite")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "removed"})
}
