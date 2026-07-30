package handlers

import "testing"

func TestEnrollmentServerIDIsStableAndServerSpecific(t *testing.T) {
	first := enrollmentServerID("server-a-secret")
	if first == "" || len(first) != 16 {
		t.Fatalf("unexpected server id %q", first)
	}
	if first != enrollmentServerID("server-a-secret") {
		t.Fatal("same server secret must produce the same id")
	}
	if first == enrollmentServerID("server-b-secret") {
		t.Fatal("different server secrets must not share enrollment server ids")
	}
}
