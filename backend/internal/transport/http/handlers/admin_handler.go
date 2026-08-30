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
)

type AdminHandler struct {
	userService *application.UserService
}

func NewAdminHandler(userService *application.UserService) *AdminHandler {
	return &AdminHandler{userService: userService}
}

func (h *AdminHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = 20
	}

	users, total, err := h.userService.GetUsers(r.Context(), page, perPage)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list users")
		return
	}

	items := make([]dto.UserDTO, 0, len(users))
	for _, u := range users {
		items = append(items, dto.UserDTO{
			ID:       u.ID.String(),
			Email:    u.Email,
			Username: u.Username,
			Role:     string(u.Role),
		})
	}
	respondPaginated(w, items, page, perPage, total)
}

type UpdateRoleRequest struct {
	Role string `json:"role"`
}

func (h *AdminHandler) UpdateUserRole(w http.ResponseWriter, r *http.Request) {
	userID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid user id")
		return
	}

	var req UpdateRoleRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	role := domain.Role(req.Role)
	if !role.IsValid() {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid role")
		return
	}

	if err := h.userService.UpdateUserRole(r.Context(), userID, role); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "user not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update role")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// DeleteUser traite une demande d'effacement recue hors application (mail,
// courrier) : l'administrateur supprime le compte a la place de la personne.
// Meme effet que DELETE /users/me, voir docs/rgpd.md.
func (h *AdminHandler) DeleteUser(w http.ResponseWriter, r *http.Request) {
	userID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid user id")
		return
	}

	if err := h.userService.DeleteUser(r.Context(), userID); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "user not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete user")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
