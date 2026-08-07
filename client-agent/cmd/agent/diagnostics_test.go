package main

import (
	"context"
	"testing"
	"time"
)

func TestDiagnosticCancellationStopsWorkAndReportsCancelled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	progress := make(chan diagnosticProgress, 8)
	result := make(chan diagnosticResult, 1)
	done := make(chan struct{})
	go func() {
		runDiagnostic(ctx, diagnosticRequest{ID: "cancel-1", Test: "cpu_stress"}, newDiagnosticPauseGate(), progress, result)
		close(done)
	}()
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("diagnostic did not terminate after cancellation")
	}
	got := <-result
	if got.ID != "cancel-1" || got.Status != "cancelled" {
		t.Fatalf("unexpected cancellation result: %#v", got)
	}
}

func TestCompleteDiagnosticCatalogHasThirtyTwoGroupedTests(t *testing.T) {
	if len(completeDiagnosticTests) != 32 {
		t.Fatalf("complete suite has %d tests, expected 32", len(completeDiagnosticTests))
	}
	seen := map[string]bool{}
	for _, test := range completeDiagnosticTests {
		if seen[test] {
			t.Fatalf("duplicate test in complete suite: %s", test)
		}
		seen[test] = true
		if diagnosticGroups[test] == "" {
			t.Fatalf("test without component group: %s", test)
		}
	}
}
