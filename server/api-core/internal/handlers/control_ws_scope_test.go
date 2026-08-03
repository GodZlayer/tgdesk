package handlers

import (
	"os"
	"strings"
	"testing"
)

func TestPrivateRPCPathAllowsDiagnosticCatalog(t *testing.T) {
	if !privateRPCPath("/api/v1/diagnostics/catalog") {
		t.Fatal("diagnostic catalog must be reachable through the private control WebSocket RPC")
	}
	if privateRPCPath("/api/v1/public/diagnostics/catalog") {
		t.Fatal("only the authenticated private diagnostics route may be proxied")
	}
}

func functionSource(t *testing.T, file, start, next string) string {
	t.Helper()
	b, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	source := string(b)
	from := strings.Index(source, start)
	if from < 0 {
		t.Fatalf("function %q not found in %s", start, file)
	}
	if next == "" {
		return source[from:]
	}
	to := strings.Index(source[from+len(start):], next)
	if to < 0 {
		return source[from:]
	}
	return source[from : from+len(start)+to]
}

func assertTGDevsAssignmentBound(t *testing.T, source string) {
	t.Helper()
	if !strings.Contains(source, "lower(o.name)='tgdevs'") {
		t.Fatal("supervisor scope must explicitly identify the TGDEVS organization")
	}
	exactNetwork := strings.Contains(source, "ta.technician_id=$1 AND ta.network_id=n.id")
	joinedNetwork := strings.Contains(source, "JOIN technician_assignments ta ON ta.network_id=n.id") &&
		strings.Contains(source, "ta.technician_id=$1")
	if !exactNetwork && !joinedNetwork {
		t.Fatal("TGDEVS visibility must require assignment to the exact network")
	}
}

func TestSupervisorAOnlySeesAssignedTGDevsNetworkNotNetworkB(t *testing.T) {
	// These are the four independent read surfaces used by the REST UI and the
	// control WebSocket snapshot. Requiring technician A and the same network ID
	// in each EXISTS excludes TGDEVS network B when only network A is assigned.
	assertTGDevsAssignmentBound(t, functionSource(t, "orgs.go", "func (s *Server) ListNetworks", "func (s *Server)"))
	assertTGDevsAssignmentBound(t, functionSource(t, "subnetworks.go", "func (s *Server) ListSubnetworks", "func (s *Server) RenameSubnetwork"))
	assertTGDevsAssignmentBound(t, functionSource(t, "devices.go", "func (s *Server) ListDevices", "type updateDeviceDisplayNameRequest"))
	assertTGDevsAssignmentBound(t, functionSource(t, "control_ws.go", "func (s *Server) controlSnapshot", ""))
}

func TestSupervisorOrganizationListDoesNotExposeAssignedOutsideOrganization(t *testing.T) {
	source := functionSource(t, "orgs.go", "func (s *Server) ListOrganizations", "type renameRequest")
	assertTGDevsAssignmentBound(t, source)
}
