package user

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	pkgerrors "github.com/josephtindall/haven/pkg/errors"
	"github.com/josephtindall/haven/pkg/middleware"
)

// Handler serves all user-related HTTP endpoints.
type Handler struct {
	svc *Service
}

// NewHandler constructs the user handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// GetUser handles GET /api/haven/users/{id}.
func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	u, err := h.svc.GetByID(r.Context(), id)
	if err != nil {
		writeError(w, pkgerrors.HTTPStatus(err), err.Error())
		return
	}
	writeJSON(w, http.StatusOK, u)
}

// UpdateProfile handles PUT /api/haven/users/me/profile.
func (h *Handler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req struct {
		DisplayName string `json:"display_name"`
		Email       string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}

	err := h.svc.UpdateProfile(r.Context(), claims.Subject, UpdateProfileParams{
		DisplayName: req.DisplayName,
		Email:       req.Email,
	})
	if err != nil {
		writeError(w, pkgerrors.HTTPStatus(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ChangePassword handles POST /api/haven/users/me/password.
func (h *Handler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}

	err := h.svc.ChangePassword(r.Context(), claims.Subject, ChangePasswordParams{
		CurrentPassword: req.CurrentPassword,
		NewPassword:     req.NewPassword,
	})
	if err != nil {
		writeError(w, pkgerrors.HTTPStatus(err), err.Error())
		return
	}
	// TODO: call session.Service.RevokeAllForUser after password change
	w.WriteHeader(http.StatusNoContent)
}

// LockUser handles POST /api/haven/admin/users/{id}/lock — owner only.
func (h *Handler) LockUser(w http.ResponseWriter, r *http.Request) {
	// TODO: verify caller is instance-owner role
	// TODO: call svc.LockAccount
	w.WriteHeader(http.StatusNoContent)
}

// UnlockUser handles DELETE /api/haven/admin/users/{id}/lock — owner only.
func (h *Handler) UnlockUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	// TODO: verify caller is instance-owner role
	if err := h.svc.UnlockAccount(r.Context(), id); err != nil {
		writeError(w, pkgerrors.HTTPStatus(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(pkgerrors.ErrorResponse{
		Code:    http.StatusText(status),
		Message: msg,
	})
}
