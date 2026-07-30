package handlers

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestBrandJSONIncludesIntegrityAndCacheVersion(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("BRANDING_DIR", dir)
	logo := []byte("\x89PNG\r\n\x1a\nTGDesk")
	favicon := []byte{0, 0, 1, 0, 1, 0, 16, 16}
	if err := os.WriteFile(filepath.Join(dir, "logo.png"), logo, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "favicon.ico"), favicon, 0600); err != nil {
		t.Fatal(err)
	}
	updated := time.Unix(1700000000, 123).UTC()
	got := brandJSON(brandRecord{
		Enabled: true, Name: "TG", LogoFile: "logo.png",
		FaviconFile: "favicon.ico", UpdatedAt: updated,
	}, true)
	if got["asset_version"] != updated.UnixNano() {
		t.Fatalf("asset cache version missing: %#v", got)
	}
	if got["logo_sha256"] == "" || got["favicon_sha256"] == "" {
		t.Fatalf("asset hashes missing: %#v", got)
	}
	if got["logo_base64"] != base64.StdEncoding.EncodeToString(logo) {
		t.Fatal("logo payload mismatch")
	}
	if readBrandLogo("../logo.png") != nil {
		t.Fatal("path traversal must be rejected")
	}
}

func TestBrandingChangeTriggersLiveRefresh(t *testing.T) {
	if brandingChanged("same", "same") {
		t.Fatal("unchanged branding must not emit duplicate refresh")
	}
	if !brandingChanged("old:1", "new:2") {
		t.Fatal("changed version must trigger live refresh")
	}
}
