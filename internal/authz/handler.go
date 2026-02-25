package authz

import (
	"encoding/json"
	"net/http"
)

// Handler serves POST /api/haven/authz/check.
type Handler struct {
	authz Authorizer
}

// NewHandler constructs the authz handler.
func NewHandler(authz Authorizer) *Handler {
	return &Handler{authz: authz}
}

// Check handles POST /api/haven/authz/check.
// Called by Luma before every protected action.
func (h *Handler) Check(w http.ResponseWriter, r *http.Request) {
	var req CheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"code":    "BAD_REQUEST",
			"message": "invalid body",
		})
		return
	}

	result, err := h.authz.Check(r.Context(), req)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"code":    "INTERNAL_ERROR",
			"message": "permission check failed",
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(result)
}
