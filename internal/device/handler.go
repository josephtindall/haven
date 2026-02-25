package device

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	pkgerrors "github.com/josephtindall/haven/pkg/errors"
	"github.com/josephtindall/haven/pkg/middleware"
)

// Handler serves device management endpoints.
type Handler struct {
	svc *Service
}

// NewHandler constructs the device handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// List handles GET /api/haven/devices.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	devices, err := h.svc.ListForUser(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, pkgerrors.HTTPStatus(err), err.Error())
		return
	}
	writeJSON(w, http.StatusOK, devices)
}

// Revoke handles DELETE /api/haven/devices/{id}.
func (h *Handler) Revoke(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	deviceID := chi.URLParam(r, "id")
	if err := h.svc.Revoke(r.Context(), deviceID, claims.Subject); err != nil {
		writeError(w, pkgerrors.HTTPStatus(err), err.Error())
		return
	}
	// TODO: call session.Service.RevokeAllForDevice(deviceID)
	// TODO: write device_revoked audit event
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
