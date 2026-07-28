package versioning

import "testing"

func TestCompare(t *testing.T) {
	tests := []struct {
		left, right string
		want        int
	}{
		{"0.3.22", "0.3.9", 1},
		{"0.3.9", "0.3.22", -1},
		{"0.3.22", "0.3.22", 0},
		{"0.3.22.0", "0.3.22", 0},
	}
	for _, test := range tests {
		if got := Compare(test.left, test.right); got != test.want {
			t.Fatalf("Compare(%q, %q) = %d, want %d",
				test.left, test.right, got, test.want)
		}
	}
}
