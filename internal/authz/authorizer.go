package authz

import (
	"context"
	"fmt"
)

// Resource identifies the target of a permission check.
type Resource struct {
	Type    string // e.g. "page", "task", "vault"
	ID      string
	VaultID string
}

// CheckRequest is the body of POST /api/haven/authz/check.
type CheckRequest struct {
	UserID       string `json:"user_id"`
	Action       string `json:"action"`        // e.g. "page:edit"
	ResourceType string `json:"resource_type"` // e.g. "page"
	ResourceID   string `json:"resource_id"`
	VaultID      string `json:"vault_id"`
}

// CheckResult is the response body.
type CheckResult struct {
	Allowed bool   `json:"allowed"`
	Reason  string `json:"reason,omitempty"` // populated only when Allowed=false
}

// Authorizer evaluates the four-dimension permission model.
// Implementations may cache results in Redis (5-min TTL).
type Authorizer interface {
	Check(ctx context.Context, req CheckRequest) (CheckResult, error)
}

// Repository provides the data the authorizer needs.
type Repository interface {
	// GetInstanceRole returns the policy set for the user's instance role.
	GetInstanceRole(ctx context.Context, userID string) ([]PolicyStatement, error)

	// GetVaultRole returns the policy set for the user's role in a vault.
	GetVaultRole(ctx context.Context, userID, vaultID string) ([]PolicyStatement, error)

	// GetResourcePermission returns explicit resource-level allow/deny for the user.
	GetResourcePermission(ctx context.Context, userID, resourceType, resourceID string) (*ResourcePermission, error)

	// IsFeatureEnabled returns whether a top-level feature flag is set on the instance.
	IsFeatureEnabled(ctx context.Context, feature string) (bool, error)
}

// PolicyStatement is a single allow/deny rule from a policy.
type PolicyStatement struct {
	Effect        string   // "allow" | "deny"
	Actions       []string // e.g. ["page:edit", "page:read"]
	ResourceTypes []string // e.g. ["page"]
}

// ResourcePermission is an explicit allow/deny for a specific user+resource.
type ResourcePermission struct {
	Effect  string   // "allow" | "deny"
	Actions []string
}

// DefaultAuthorizer implements the four-dimension evaluation algorithm.
type DefaultAuthorizer struct {
	repo Repository
}

// NewAuthorizer constructs the default authorizer.
func NewAuthorizer(repo Repository) *DefaultAuthorizer {
	return &DefaultAuthorizer{repo: repo}
}

// Check evaluates all four permission dimensions in strict order.
// Explicit deny at any level always wins and stops evaluation immediately.
//
// Evaluation order (most→least specific):
//  1. Feature flag (instance-level)
//  2. Resource-level explicit deny
//  3. Resource-level explicit allow
//  4. Vault role policies
//  5. Instance role policies
//  6. Default → DENY
func (a *DefaultAuthorizer) Check(ctx context.Context, req CheckRequest) (CheckResult, error) {
	// 1. Feature flag.
	featureKey := domainOf(req.Action)
	enabled, err := a.repo.IsFeatureEnabled(ctx, featureKey)
	if err != nil {
		return CheckResult{}, fmt.Errorf("authz: feature flag: %w", err)
	}
	if !enabled {
		return CheckResult{Allowed: false, Reason: "feature_disabled"}, nil
	}

	// 2 & 3. Resource-level explicit permission.
	rp, err := a.repo.GetResourcePermission(ctx, req.UserID, req.ResourceType, req.ResourceID)
	if err != nil {
		return CheckResult{}, fmt.Errorf("authz: resource permission: %w", err)
	}
	if rp != nil {
		if rp.Effect == "deny" && containsAction(rp.Actions, req.Action) {
			return CheckResult{Allowed: false, Reason: "resource_explicit_deny"}, nil
		}
		if rp.Effect == "allow" && containsAction(rp.Actions, req.Action) {
			return CheckResult{Allowed: true}, nil
		}
	}

	// 4. Vault role.
	vaultPolicies, err := a.repo.GetVaultRole(ctx, req.UserID, req.VaultID)
	if err != nil {
		return CheckResult{}, fmt.Errorf("authz: vault role: %w", err)
	}
	if result, ok := evaluatePolicies(vaultPolicies, req.Action, "vault_role"); ok {
		return result, nil
	}

	// 5. Instance role.
	instancePolicies, err := a.repo.GetInstanceRole(ctx, req.UserID)
	if err != nil {
		return CheckResult{}, fmt.Errorf("authz: instance role: %w", err)
	}
	if result, ok := evaluatePolicies(instancePolicies, req.Action, "instance_role"); ok {
		return result, nil
	}

	// 6. Default deny.
	return CheckResult{Allowed: false, Reason: "default_deny"}, nil
}

// evaluatePolicies scans a list of policy statements for the action.
// Returns (result, true) if a matching statement was found, (zero, false) otherwise.
// Deny takes precedence over allow within the same policy set.
func evaluatePolicies(stmts []PolicyStatement, action, source string) (CheckResult, bool) {
	for _, s := range stmts {
		if !containsAction(s.Actions, action) {
			continue
		}
		if s.Effect == "deny" {
			return CheckResult{Allowed: false, Reason: source + "_deny"}, true
		}
	}
	for _, s := range stmts {
		if !containsAction(s.Actions, action) {
			continue
		}
		if s.Effect == "allow" {
			return CheckResult{Allowed: true}, true
		}
	}
	return CheckResult{}, false
}

func containsAction(actions []string, target string) bool {
	for _, a := range actions {
		if a == target {
			return true
		}
	}
	return false
}

// domainOf extracts the domain from "domain:action" (e.g. "page" from "page:edit").
func domainOf(action string) string {
	for i, c := range action {
		if c == ':' {
			return action[:i]
		}
	}
	return action
}
