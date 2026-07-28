package versioning

import (
	"strconv"
	"strings"
)

func Compare(left, right string) int {
	parse := func(version string) []int {
		parts := strings.Split(strings.TrimPrefix(strings.TrimSpace(version), "v"), ".")
		values := make([]int, len(parts))
		for index, part := range parts {
			value, err := strconv.Atoi(part)
			if err != nil || value < 0 {
				return nil
			}
			values[index] = value
		}
		return values
	}
	a, b := parse(left), parse(right)
	if a == nil || b == nil {
		return 0
	}
	size := len(a)
	if len(b) > size {
		size = len(b)
	}
	for index := 0; index < size; index++ {
		var av, bv int
		if index < len(a) {
			av = a[index]
		}
		if index < len(b) {
			bv = b[index]
		}
		if av < bv {
			return -1
		}
		if av > bv {
			return 1
		}
	}
	return 0
}
