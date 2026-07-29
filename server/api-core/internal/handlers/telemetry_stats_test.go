package handlers

import "testing"

func TestSustainedUsageLevels(t *testing.T) {
	cases := []struct {
		average float64
		samples int
		want    string
	}{
		{99, 2, "normal"},
		{74.99, 30, "normal"},
		{75, 30, "warning"},
		{85, 30, "critical"},
		{95, 30, "maximum"},
	}
	for _, tc := range cases {
		if got := sustainedUsageLevel(tc.average, tc.samples); got != tc.want {
			t.Fatalf("average %.2f with %d samples: got %q, want %q",
				tc.average, tc.samples, got, tc.want)
		}
	}
}

func TestHealthUsesAverageInsteadOfCurrentSample(t *testing.T) {
	var current = 99.0
	hardware := hardwareSample{}
	hardware.CPU.Usage = &current

	health := analyzeHardwareHealth(
		hardware,
		metricStats{Average: 20, Samples: 30},
		metricStats{Average: 30, Samples: 30},
		metricStats{},
		metricStats{},
		metricStats{},
		30,
	)
	if got := health["level"]; got != "normal" {
		t.Fatalf("instantaneous spike raised health level: got %v", got)
	}
}
