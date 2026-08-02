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
		runDiagnostic(ctx, diagnosticRequest{ID: "cancel-1", Test: "cpu_stress"}, progress, result)
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
