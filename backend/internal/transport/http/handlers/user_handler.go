package handlers

import (
	"errors"
	"net/http"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/transport/http/dto"
	"github.com/streampulse/backend/internal/transport/http/middleware"
)

// UserHandler sert le compte de la personne connectee : consultation de ses
// donnees et suppression de son compte, les deux droits RGPD que l'API doit
// rendre exercables sans passer par un administrateur (docs/rgpd.md).
type UserHandler struct {
	userService *application.UserService
}

func NewUserHandler(userService *application.UserService) *UserHandler {
	return &UserHandler{userService: userService}
}

// currentUserID lit l'identifiant du compte dans les claims posees par le
// middleware d'authentification. Une reponse a deja ete ecrite si elle
// renvoie false.
func currentUserID(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	claims := middleware.GetClaims(r.Context())
	if claims == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return uuid.Nil, false
	}
	id, err := uuid.Parse(claims.UserID)
	if err != nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid user id")
		return uuid.Nil, false
	}
	return id, true
}

// Me renvoie les donnees du compte telles qu'elles sont en base, et non
// celles du jeton : apres une suppression, un jeton encore valide obtient
// 404, ce qui prouve que le compte n'existe plus.
func (h *UserHandler) Me(w http.ResponseWriter, r *http.Request) {
	id, ok := currentUserID(w, r)
	if !ok {
		return
	}

	user, err := h.userService.GetUser(r.Context(), id)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "user not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to load profile")
		return
	}

	respondJSON(w, http.StatusOK, dto.ProfileDTO{
		ID:        user.ID.String(),
		Email:     user.Email,
		Username:  user.Username,
		Role:      string(user.Role),
		CreatedAt: user.CreatedAt,
		UpdatedAt: user.UpdatedAt,
	})
}

type UpdateProfileRequest struct {
	Email    string `json:"email"`
	Username string `json:"username"`
}

// UpdateMe change l'email et le nom d'utilisateur du compte connecte. C'est
// le droit de rectification (RGPD art. 16) : jusqu'ici seul un administrateur
// pouvait le faire, directement en base (docs/rgpd.md).
func (h *UserHandler) UpdateMe(w http.ResponseWriter, r *http.Request) {
	id, ok := currentUserID(w, r)
	if !ok {
		return
	}

	var req UpdateProfileRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	user, err := h.userService.UpdateProfile(r.Context(), id, req.Email, req.Username)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrInvalidInput):
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid email or username")
		case errors.Is(err, domain.ErrAlreadyExists):
			respondError(w, http.StatusConflict, "CONFLICT", "email already registered")
		case errors.Is(err, domain.ErrNotFound):
			respondError(w, http.StatusNotFound, "NOT_FOUND", "user not found")
		default:
			respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update profile")
		}
		return
	}

	respondJSON(w, http.StatusOK, dto.ProfileDTO{
		ID:        user.ID.String(),
		Email:     user.Email,
		Username:  user.Username,
		Role:      string(user.Role),
		CreatedAt: user.CreatedAt,
		UpdatedAt: user.UpdatedAt,
	})
}

// DeleteMe efface le compte de la personne connectee. Le jeton d'acces en
// cours reste techniquement valide jusqu'a son expiration (15 min par
// defaut, ADR 006) mais ne peut plus rien faire d'utile : le compte, ses
// refresh tokens et ses donnees n'existent plus.
func (h *UserHandler) DeleteMe(w http.ResponseWriter, r *http.Request) {
	id, ok := currentUserID(w, r)
	if !ok {
		return
	}

	if err := h.userService.DeleteUser(r.Context(), id); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "user not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete account")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
