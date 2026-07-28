package handlers

import "testing"

func TestUpdateAvailableNeverDowngrades(t *testing.T) {
	if updateAvailable("0.3.22", "0.3.9") {
		t.Fatal("server must not offer an older release")
	}
	if !updateAvailable("0.3.9", "0.3.22") {
		t.Fatal("server should offer a newer release")
	}
	if updateAvailable("0.3.22", "0.3.22") {
		t.Fatal("server must not offer the installed release")
	}
}
