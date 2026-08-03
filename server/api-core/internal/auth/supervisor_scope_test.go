package auth

import (
	"os"
	"strings"
	"testing"
)

func authFunctionSource(t *testing.T, start, next string) string {
	t.Helper()
	b, err := os.ReadFile("authorizer.go")
	if err != nil {
		t.Fatal(err)
	}
	source := string(b)
	from := strings.Index(source, start)
	if from < 0 {
		t.Fatalf("function %q not found", start)
	}
	to := strings.Index(source[from+len(start):], next)
	if to < 0 {
		return source[from:]
	}
	return source[from : from+len(start)+to]
}

func TestSupervisorAccessChecksBindTGDevsToExactAssignment(t *testing.T) {
	checks := []string{
		authFunctionSource(t, "func (a *Authorizer) CanAccessDevice", "func (a *Authorizer) CanAccessNetwork"),
		authFunctionSource(t, "func (a *Authorizer) CanAccessNetwork", "func (a *Authorizer) CanAccessOrganization"),
		authFunctionSource(t, "func (a *Authorizer) CanAccessOrganization", "func (a *Authorizer) CanCreateDevice"),
	}
	for _, source := range checks {
		if !strings.Contains(source, "lower(o.name)='tgdevs'") {
			t.Fatal("access check does not constrain the secondary organization to TGDEVS")
		}
		if !strings.Contains(source, "ta.technician_id=$1") {
			t.Fatal("access check does not bind TGDEVS access to the requesting supervisor")
		}
	}
	for _, source := range checks[:2] {
		if !strings.Contains(source, "ta.network_id=n.id") {
			t.Fatal("supervisor A could see TGDEVS network B without exact network assignment")
		}
	}
}
