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

type PlaylistHandler struct {
	playlistService *application.PlaylistService
}

func NewPlaylistHandler(playlistService *application.PlaylistService) *PlaylistHandler {
	return &PlaylistHandler{playlistService: playlistService}
}

func (h *PlaylistHandler) ListPlaylists(w http.ResponseWriter, r *http.Request) {
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

	ownerID, _ := uuid.Parse(claims.UserID)
	playlists, total, err := h.playlistService.ListPlaylists(r.Context(), ownerID, page, perPage)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list playlists")
		return
	}

	items := make([]dto.PlaylistResponse, 0, len(playlists))
	for _, p := range playlists {
		items = append(items, toPlaylistResponse(&p))
	}
	respondPaginated(w, items, page, perPage, total)
}

func (h *PlaylistHandler) CreatePlaylist(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	var req dto.CreatePlaylistRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	ownerID, _ := uuid.Parse(claims.UserID)
	playlist, err := h.playlistService.CreatePlaylist(r.Context(), application.CreatePlaylistInput{
		Name:     req.Name,
		OwnerID:  ownerID,
		IsPublic: req.IsPublic,
	})
	if err != nil {
		if errors.Is(err, domain.ErrInvalidInput) {
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create playlist")
		return
	}

	respondJSON(w, http.StatusCreated, toPlaylistResponse(playlist))
}

func (h *PlaylistHandler) GetPlaylist(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid playlist id")
		return
	}

	requesterID, _ := uuid.Parse(claims.UserID)
	playlist, err := h.playlistService.GetPlaylist(r.Context(), id, requesterID)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "playlist not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to get playlist")
		return
	}

	respondJSON(w, http.StatusOK, toPlaylistResponse(playlist))
}

func (h *PlaylistHandler) UpdatePlaylist(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid playlist id")
		return
	}

	var req dto.UpdatePlaylistRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	ownerID, _ := uuid.Parse(claims.UserID)
	playlist, err := h.playlistService.UpdatePlaylist(r.Context(), application.UpdatePlaylistInput{
		ID:       id,
		Name:     req.Name,
		IsPublic: req.IsPublic,
		OwnerID:  ownerID,
	})
	if err != nil {
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this playlist")
			return
		}
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "playlist not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update playlist")
		return
	}

	respondJSON(w, http.StatusOK, toPlaylistResponse(playlist))
}

func (h *PlaylistHandler) DeletePlaylist(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid playlist id")
		return
	}

	ownerID, _ := uuid.Parse(claims.UserID)
	if err := h.playlistService.DeletePlaylist(r.Context(), id, ownerID); err != nil {
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this playlist")
			return
		}
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "playlist not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete playlist")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (h *PlaylistHandler) AddTrack(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	playlistID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid playlist id")
		return
	}

	var req dto.AddTrackRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	ownerID, _ := uuid.Parse(claims.UserID)
	track, err := h.playlistService.AddTrack(r.Context(), application.AddTrackInput{
		PlaylistID: playlistID,
		OwnerID:    ownerID,
		Title:      req.Title,
		URL:        req.URL,
		Duration:   req.Duration,
	})
	if err != nil {
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this playlist")
			return
		}
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "playlist not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to add track")
		return
	}

	respondJSON(w, http.StatusCreated, dto.TrackResponse{
		ID:       track.ID.String(),
		Title:    track.Title,
		URL:      track.URL,
		Duration: track.Duration,
		Position: track.Position,
	})
}

func (h *PlaylistHandler) ReorderTracks(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	playlistID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid playlist id")
		return
	}

	var req dto.ReorderTracksRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	trackIDs := make([]uuid.UUID, 0, len(req.TrackIDs))
	for _, raw := range req.TrackIDs {
		trackID, err := uuid.Parse(raw)
		if err != nil {
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid track id: "+raw)
			return
		}
		trackIDs = append(trackIDs, trackID)
	}

	ownerID, _ := uuid.Parse(claims.UserID)
	playlist, err := h.playlistService.ReorderTracks(r.Context(), application.ReorderTracksInput{
		PlaylistID: playlistID,
		OwnerID:    ownerID,
		TrackIDs:   trackIDs,
	})
	if err != nil {
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this playlist")
			return
		}
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "playlist or track not found")
			return
		}
		if errors.Is(err, domain.ErrInvalidInput) {
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to reorder tracks")
		return
	}

	respondJSON(w, http.StatusOK, toPlaylistResponse(playlist))
}

func (h *PlaylistHandler) RemoveTrack(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	playlistID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid playlist id")
		return
	}

	trackID, err := uuid.Parse(chi.URLParam(r, "trackId"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid track id")
		return
	}

	ownerID, _ := uuid.Parse(claims.UserID)
	if err := h.playlistService.RemoveTrack(r.Context(), playlistID, trackID, ownerID); err != nil {
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "not the owner of this playlist")
			return
		}
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "track not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to remove track")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "removed"})
}

func toPlaylistResponse(p *domain.Playlist) dto.PlaylistResponse {
	tracks := make([]dto.TrackResponse, 0, len(p.Tracks))
	for _, t := range p.Tracks {
		tracks = append(tracks, dto.TrackResponse{
			ID:       t.ID.String(),
			Title:    t.Title,
			URL:      t.URL,
			Duration: t.Duration,
			Position: t.Position,
		})
	}
	return dto.PlaylistResponse{
		ID:        p.ID.String(),
		Name:      p.Name,
		OwnerID:   p.OwnerID.String(),
		IsPublic:  p.IsPublic,
		Tracks:    tracks,
		CreatedAt: p.CreatedAt,
		UpdatedAt: p.UpdatedAt,
	}
}
