//go:build !windows

package main

// The production collector is Windows-only. The cancellation test exercises
// cpu_stress and only needs this stub to compile diagnostics.go on CI Linux.
func collectHardwareSnapshot() map[string]any {
	return map[string]any{}
}
