package preferences

import (
	"encoding/json"
	"net/http"

	pkgerrors "github.com/josephtindall/haven/pkg/errors"
	"github.com/josephtindall/haven/pkg/middleware"
)

// Handler serves the user preferences endpoints.
type Handler struct {
	svc *Service
}

// NewHandler constructs the preferences handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// Get handles GET /api/haven/users/me/preferences.
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	p, err := h.svc.Get(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, pkgerrors.HTTPStatus(err), err.Error())
		return
	}
	writeJSON(w, http.StatusOK, p)
}

// Update handles PATCH /api/haven/users/me/preferences.
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var params UpdateParams
	if err := json.NewDecoder(r.Body).Decode(&params); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}

	if err := h.svc.Update(r.Context(), claims.Subject, params); err != nil {
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
