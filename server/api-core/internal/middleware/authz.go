package middleware

import (
	"context"
	"net/http"

	"tgdesk/api-core/internal/auth"
)

type authzKey string

const authzContextKey authzKey = "authz"

// WithAuthorizer enriches the request context with an authorizer instance.
// Must run after RequireAuth middleware.
func WithAuthorizer(authorizer *auth.Authorizer) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// The claims should already be in context from RequireAuth
			claims := ClaimsFrom(r.Context())
			if claims == nil {
				http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
				return
			}

			// Store authorizer in context for handler use
			ctx := context.WithValue(r.Context(), authzContextKey, authorizer)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// AuthorizerFrom extracts the authorizer from request context.
func AuthorizerFrom(ctx context.Context) *auth.Authorizer {
	authz, _ := ctx.Value(authzContextKey).(*auth.Authorizer)
	return authz
}

// RequirePermission is a middleware factory that checks a permission.
// Returns true if the permission is granted, false otherwise.
type PermissionChecker func(ctx context.Context, claims *auth.Claims, authorizer *auth.Authorizer) (bool, error)

// CheckPermission runs a permission check and returns 403 if denied.
func CheckPermission(checker PermissionChecker) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims := ClaimsFrom(r.Context())
			authorizer := AuthorizerFrom(r.Context())

			if claims == nil || authorizer == nil {
				http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
				return
			}

			allowed, err := checker(r.Context(), claims, authorizer)
			if err != nil {
				http.Error(w, `{"error":"permission check failed"}`, http.StatusInternalServerError)
				return
			}

			if !allowed {
				http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
