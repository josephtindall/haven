package authz

import (
	"encoding/json"
	"net/http"

	"github.com/josephtindall/haven/internal/audit"
	pkgerrors "github.com/josephtindall/haven/pkg/errors"
	pkgmiddleware "github.com/josephtindall/haven/pkg/middleware"
)

// Handler serves POST /api/haven/authz/check.
type Handler struct {
	authz Authorizer
	audit audit.Service
}

// NewHandler constructs the authz handler.
func NewHandler(authz Authorizer, auditSvc audit.Service) *Handler {
	return &Handler{authz: authz, audit: auditSvc}
}

// Check handles POST /api/haven/authz/check.
// Called by Luma before every protected action.
func (h *Handler) Check(w http.ResponseWriter, r *http.Request) {
	var req CheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}

	result, err := h.authz.Check(r.Context(), req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "permission check failed")
		return
	}

	if !result.Allowed {
		claims := pkgmiddleware.ClaimsFromContext(r.Context())
		deviceID := ""
		userID := ""
		if claims != nil {
			userID = claims.Subject
			deviceID = claims.DeviceID
		}
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID:   userID,
			DeviceID: deviceID,
			Event:    audit.EventAuthzDenied,
			Metadata: map[string]any{
				"action":        req.Action,
				"resource_type": req.ResourceType,
				"resource_id":   req.ResourceID,
			},
		})
	}

	writeJSON(w, http.StatusOK, result)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(pkgerrors.ErrorResponse{
		Code:    code,
		Message: msg,
	})
}
