package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/transport/http/dto"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

type MusicHandler struct {
	musicService *application.MusicService
	streamRepo   domain.StreamRepository
}

func NewMusicHandler(musicService *application.MusicService, streamRepo domain.StreamRepository) *MusicHandler {
	return &MusicHandler{
		musicService: musicService,
		streamRepo:   streamRepo,
	}
}

func (h *MusicHandler) ListMusic(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = 20
	}

	tracks, total, err := h.musicService.ListMusic(r.Context(), page, perPage)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list music")
		return
	}

	items := make([]dto.MusicResponse, 0, len(tracks))
	for _, m := range tracks {
		items = append(items, toMusicResponse(&m))
	}
	respondPaginated(w, items, page, perPage, total)
}

func (h *MusicHandler) GetMusic(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "INVALID_ID", "invalid music id")
		return
	}

	music, err := h.musicService.GetMusic(r.Context(), id)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "music not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to get music")
		return
	}

	respondJSON(w, http.StatusOK, toMusicResponse(music))
}

func (h *MusicHandler) UploadMusic(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	uploaderID, err := uuid.Parse(claims.UserID)
	if err != nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user id")
		return
	}

	contentType := r.Header.Get("Content-Type")

	// JSON body for URL-based addition
	if strings.HasPrefix(contentType, "application/json") {
		var req dto.AddMusicURLRequest
		if err := decodeJSON(r, &req); err != nil {
			respondError(w, http.StatusBadRequest, "INVALID_BODY", "invalid request body")
			return
		}

		music, err := h.musicService.AddMusicByURL(r.Context(), req.Title, req.Artist, req.Album, req.Duration, req.URL, uploaderID)
		if err != nil {
			if errors.Is(err, domain.ErrInvalidInput) {
				respondError(w, http.StatusBadRequest, "INVALID_INPUT", err.Error())
				return
			}
			respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to add music")
			return
		}

		respondJSON(w, http.StatusCreated, toMusicResponse(music))
		return
	}

	// Multipart form for file upload
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		respondError(w, http.StatusBadRequest, "INVALID_BODY", "failed to parse multipart form")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		respondError(w, http.StatusBadRequest, "INVALID_BODY", "file field is required")
		return
	}
	defer file.Close()

	title := r.FormValue("title")
	artist := r.FormValue("artist")
	album := r.FormValue("album")
	duration, _ := strconv.Atoi(r.FormValue("duration"))

	music, err := h.musicService.UploadMusic(r.Context(), title, artist, album, duration, header.Filename, file, uploaderID)
	if err != nil {
		if errors.Is(err, domain.ErrInvalidInput) {
			respondError(w, http.StatusBadRequest, "INVALID_INPUT", err.Error())
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to upload music")
		return
	}

	respondJSON(w, http.StatusCreated, toMusicResponse(music))
}

func (h *MusicHandler) SearchMusic(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	if query == "" {
		respondError(w, http.StatusBadRequest, "INVALID_INPUT", "query parameter q is required")
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

	tracks, total, err := h.musicService.SearchMusic(r.Context(), query, page, perPage)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to search music")
		return
	}

	items := make([]dto.MusicResponse, 0, len(tracks))
	for _, m := range tracks {
		items = append(items, toMusicResponse(&m))
	}
	respondPaginated(w, items, page, perPage, total)
}

func (h *MusicHandler) UpdateMusic(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	ownerID, err := uuid.Parse(claims.UserID)
	if err != nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user id")
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "INVALID_ID", "invalid music id")
		return
	}

	var req dto.UpdateMusicRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	music, err := h.musicService.UpdateMusic(r.Context(), id, ownerID, req.Title, req.Artist, req.Album, req.CoverURL)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "music not found")
			return
		}
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you are not the owner of this music")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update music")
		return
	}

	respondJSON(w, http.StatusOK, toMusicResponse(music))
}

func (h *MusicHandler) DeleteMusic(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	ownerID, err := uuid.Parse(claims.UserID)
	if err != nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user id")
		return
	}

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "INVALID_ID", "invalid music id")
		return
	}

	if err := h.musicService.DeleteMusic(r.Context(), id, ownerID); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "music not found")
			return
		}
		if errors.Is(err, domain.ErrNotOwner) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you are not the owner of this music")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete music")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"message": "music deleted"})
}

func (h *MusicHandler) GlobalSearch(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	if query == "" {
		respondError(w, http.StatusBadRequest, "INVALID_INPUT", "query parameter q is required")
		return
	}

	// Search music using full-text search
	musicTracks, _, err := h.musicService.SearchMusic(r.Context(), query, 1, 20)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to search music")
		return
	}

	musicItems := make([]dto.MusicResponse, 0, len(musicTracks))
	for _, m := range musicTracks {
		musicItems = append(musicItems, toMusicResponse(&m))
	}

	// Search streams by title using List and filtering with ILIKE-style match
	streams, _, err := h.streamRepo.List(r.Context(), 1, 100)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to search streams")
		return
	}

	lowerQuery := strings.ToLower(query)
	streamItems := make([]dto.StreamResponse, 0)
	for _, s := range streams {
		if strings.Contains(strings.ToLower(s.Title), lowerQuery) {
			streamItems = append(streamItems, toStreamResponse(&s))
		}
	}

	respondJSON(w, http.StatusOK, dto.SearchResponse{
		Streams: streamItems,
		Music:   musicItems,
	})
}

func toMusicResponse(m *domain.Music) dto.MusicResponse {
	return dto.MusicResponse{
		ID:         m.ID.String(),
		Title:      m.Title,
		Artist:     m.Artist,
		Album:      m.Album,
		Duration:   m.Duration,
		URL:        m.URL,
		CoverURL:   m.CoverURL,
		UploadedBy: m.UploadedBy.String(),
		CreatedAt:  m.CreatedAt,
	}
}
