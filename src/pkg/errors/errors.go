package errors

import (
	"errors"
	"net/http"
)

// Sentinel errors returned by the service layer.
// Handlers map these to HTTP status codes via HTTPStatus.
var (
	ErrInvalidCredentials = errors.New("invalid credentials")     // 401
	ErrAccountLocked      = errors.New("account locked")          // 403
	ErrTokenExpired       = errors.New("token expired")           // 401
	ErrTokenInvalid       = errors.New("token invalid")           // 401
	ErrTokenRevoked       = errors.New("token revoked")           // 401
	ErrTokenReuseDetected = errors.New("token reuse detected")    // 401 — triggers full revocation
	ErrUserNotFound       = errors.New("user not found")          // 404
	ErrEmailTaken         = errors.New("email taken")             // 409
	ErrPasswordTooShort   = errors.New("password too short")      // 422
	ErrDeviceNotFound     = errors.New("device not found")        // 404
	ErrDeviceRevoked      = errors.New("device revoked")          // 403
	ErrForbidden          = errors.New("forbidden")               // 403
	ErrSetupRequired      = errors.New("setup required")          // 503
	ErrSetupComplete      = errors.New("setup complete")          // 410
)

// HTTPStatus maps a sentinel error to its canonical HTTP status code.
// Returns 500 for unrecognised errors.
func HTTPStatus(err error) int {
	switch {
	case errors.Is(err, ErrInvalidCredentials):
		return http.StatusUnauthorized
	case errors.Is(err, ErrAccountLocked):
		return http.StatusForbidden
	case errors.Is(err, ErrTokenExpired):
		return http.StatusUnauthorized
	case errors.Is(err, ErrTokenInvalid):
		return http.StatusUnauthorized
	case errors.Is(err, ErrTokenRevoked):
		return http.StatusUnauthorized
	case errors.Is(err, ErrTokenReuseDetected):
		return http.StatusUnauthorized
	case errors.Is(err, ErrUserNotFound):
		return http.StatusNotFound
	case errors.Is(err, ErrEmailTaken):
		return http.StatusConflict
	case errors.Is(err, ErrPasswordTooShort):
		return http.StatusUnprocessableEntity
	case errors.Is(err, ErrDeviceNotFound):
		return http.StatusNotFound
	case errors.Is(err, ErrDeviceRevoked):
		return http.StatusForbidden
	case errors.Is(err, ErrForbidden):
		return http.StatusForbidden
	case errors.Is(err, ErrSetupRequired):
		return http.StatusServiceUnavailable
	case errors.Is(err, ErrSetupComplete):
		return http.StatusGone
	default:
		return http.StatusInternalServerError
	}
}

// ErrorResponse is the JSON envelope for all error responses.
type ErrorResponse struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Is re-exports errors.Is for callers who import only this package.
var Is = errors.Is
