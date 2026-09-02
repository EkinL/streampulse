package handlers

import (
	"errors"
	"net/http"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/transport/http/dto"
)

type AuthHandler struct {
	authService *application.AuthService
}

func NewAuthHandler(authService *application.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req dto.RegisterRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	result, err := h.authService.Register(r.Context(), application.RegisterInput{
		Email:         req.Email,
		Username:      req.Username,
		Password:      req.Password,
		AcceptedTerms: req.AcceptedTerms,
	})
	if err != nil {
		if errors.Is(err, domain.ErrAlreadyExists) {
			respondError(w, http.StatusConflict, "CONFLICT", "email already registered")
			return
		}
		if errors.Is(err, domain.ErrInvalidInput) {
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "registration failed")
		return
	}

	respondJSON(w, http.StatusCreated, dto.TokenResponse{
		AccessToken:  result.AccessToken,
		RefreshToken: result.RefreshToken,
		ExpiresAt:    result.ExpiresAt,
		User: dto.UserDTO{
			ID:       result.User.ID.String(),
			Email:    result.User.Email,
			Username: result.User.Username,
			Role:     string(result.User.Role),
		},
	})
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req dto.LoginRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	result, err := h.authService.Login(r.Context(), application.LoginInput{
		Email:    req.Email,
		Password: req.Password,
	})
	if err != nil {
		if errors.Is(err, domain.ErrInvalidCredentials) {
			respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid credentials")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "login failed")
		return
	}

	respondJSON(w, http.StatusOK, dto.TokenResponse{
		AccessToken:  result.AccessToken,
		RefreshToken: result.RefreshToken,
		ExpiresAt:    result.ExpiresAt,
		User: dto.UserDTO{
			ID:       result.User.ID.String(),
			Email:    result.User.Email,
			Username: result.User.Username,
			Role:     string(result.User.Role),
		},
	})
}

// OAuthLogin ouvre une session a partir d'un ID token Google ou Apple
// (connexion sociale). Cree le compte au premier passage.
func (h *AuthHandler) OAuthLogin(w http.ResponseWriter, r *http.Request) {
	var req dto.OAuthLoginRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	result, err := h.authService.LoginWithOAuth(r.Context(), application.OAuthLoginInput{
		Provider: req.Provider,
		IDToken:  req.IDToken,
	})
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrProviderNotConfigured):
			respondError(w, http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "social login is not configured on this server")
		case errors.Is(err, domain.ErrTokenInvalid):
			respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid identity token")
		case errors.Is(err, domain.ErrAlreadyExists):
			respondError(w, http.StatusConflict, "CONFLICT", "email already registered with a password account")
		case errors.Is(err, domain.ErrInvalidInput):
			respondError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
		default:
			respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "social login failed")
		}
		return
	}

	respondJSON(w, http.StatusOK, dto.TokenResponse{
		AccessToken:  result.AccessToken,
		RefreshToken: result.RefreshToken,
		ExpiresAt:    result.ExpiresAt,
		User: dto.UserDTO{
			ID:       result.User.ID.String(),
			Email:    result.User.Email,
			Username: result.User.Username,
			Role:     string(result.User.Role),
		},
	})
}

func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req dto.RefreshRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}

	result, err := h.authService.RefreshToken(r.Context(), req.RefreshToken)
	if err != nil {
		if errors.Is(err, domain.ErrTokenExpired) || errors.Is(err, domain.ErrNotFound) {
			respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid or expired refresh token")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "token refresh failed")
		return
	}

	respondJSON(w, http.StatusOK, dto.TokenResponse{
		AccessToken:  result.AccessToken,
		RefreshToken: result.RefreshToken,
		ExpiresAt:    result.ExpiresAt,
		User: dto.UserDTO{
			ID:       result.User.ID.String(),
			Email:    result.User.Email,
			Username: result.User.Username,
			Role:     string(result.User.Role),
		},
	})
}
