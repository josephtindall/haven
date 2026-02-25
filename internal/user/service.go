package user

import (
	"context"
	"fmt"
	"strings"

	"github.com/josephtindall/haven/pkg/crypto"
	pkgerrors "github.com/josephtindall/haven/pkg/errors"
)

const (
	minPasswordLen  = 12
	maxFailedLogins = 10
)

// Service contains all business logic for user management.
// It depends on the Repository interface — never on a concrete type.
type Service struct {
	repo Repository
}

// NewService constructs a Service with the given repository.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// GetByID returns the public projection of a user.
func (s *Service) GetByID(ctx context.Context, id string) (*PublicUser, error) {
	u, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("user.Service.GetByID: %w", err)
	}
	return u.ToPublic(), nil
}

// UpdateProfile applies validated profile changes. Writes a profile_updated
// audit event — callers are responsible for passing an audit writer.
func (s *Service) UpdateProfile(ctx context.Context, id string, params UpdateProfileParams) error {
	if params.DisplayName != "" {
		params.DisplayName = strings.TrimSpace(params.DisplayName)
	}
	if params.Email != "" {
		params.Email = strings.ToLower(strings.TrimSpace(params.Email))
	}
	if err := s.repo.UpdateProfile(ctx, id, params); err != nil {
		return fmt.Errorf("user.Service.UpdateProfile: %w", err)
	}
	return nil
}

// ChangePassword validates the current password, hashes the new one, and
// updates the record. On success, all existing sessions should be revoked by
// the caller (session.Service.RevokeAllForUser).
func (s *Service) ChangePassword(ctx context.Context, id string, params ChangePasswordParams) error {
	if len(params.NewPassword) < minPasswordLen {
		return pkgerrors.ErrPasswordTooShort
	}

	u, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return fmt.Errorf("user.Service.ChangePassword get: %w", err)
	}

	ok, err := crypto.VerifyPassword(params.CurrentPassword, u.PasswordHash)
	if err != nil {
		return fmt.Errorf("user.Service.ChangePassword verify: %w", err)
	}
	if !ok {
		return pkgerrors.ErrInvalidCredentials
	}

	hash, err := crypto.HashPassword(params.NewPassword)
	if err != nil {
		return fmt.Errorf("user.Service.ChangePassword hash: %w", err)
	}

	if err := s.repo.UpdatePassword(ctx, id, hash); err != nil {
		return fmt.Errorf("user.Service.ChangePassword update: %w", err)
	}
	return nil
}

// RecordFailedLogin increments the counter and locks the account when the
// threshold is reached. IMPORTANT: this is a side effect of a failed login
// attempt — it must never reveal whether the email existed.
func (s *Service) RecordFailedLogin(ctx context.Context, id string) error {
	count, err := s.repo.IncrementFailedLogins(ctx, id)
	if err != nil {
		return fmt.Errorf("user.Service.RecordFailedLogin: %w", err)
	}
	if count >= maxFailedLogins {
		if err := s.repo.LockAccount(ctx, id, "brute force threshold reached"); err != nil {
			return fmt.Errorf("user.Service.RecordFailedLogin lock: %w", err)
		}
	}
	return nil
}

// UnlockAccount clears the lock on a user — owner-only operation.
func (s *Service) UnlockAccount(ctx context.Context, id string) error {
	if err := s.repo.UnlockAccount(ctx, id); err != nil {
		return fmt.Errorf("user.Service.UnlockAccount: %w", err)
	}
	return nil
}
