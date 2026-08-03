//go:build !windows

package main

import (
	"fmt"

	"tgdesk/agent/internal/updatecore"
)

func runApplyStagedWithStatus(staging, installDir string, parentPID uint32) error {
	return updatecore.ApplyStagedOfflineWithProgress(staging, installDir, parentPID,
		func(event updatecore.ProgressEvent) {
			fmt.Printf("%d%% %s\n", event.Percent, event.Message)
		})
}
