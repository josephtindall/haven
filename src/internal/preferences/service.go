package preferences

import (
	"context"
	"fmt"
)

// Service manages user preferences.
type Service struct {
	repo Repository
}

// NewService constructs the preferences service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// Get returns the preferences for a user.
func (s *Service) Get(ctx context.Context, userID string) (*Preferences, error) {
	p, err := s.repo.Get(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("preferences.Service.Get: %w", err)
	}
	return p, nil
}

// Update applies a partial preferences update.
func (s *Service) Update(ctx context.Context, userID string, params UpdateParams) error {
	// TODO: validate timezone (IANA), language (BCP-47), theme, date/time format
	if err := s.repo.Update(ctx, userID, params); err != nil {
		return fmt.Errorf("preferences.Service.Update: %w", err)
	}
	return nil
}
