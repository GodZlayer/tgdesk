package updatecore

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func testHash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func TestSafeModulePath(t *testing.T) {
	valid := []string{"version.txt", "data/flutter_assets/a.json", `plugins\x.dll`}
	invalid := []string{"", ".", "..", "../escape", `..\escape`, "/absolute", `C:\absolute`}
	for _, value := range valid {
		if !safeModulePath(value) {
			t.Fatalf("expected safe path: %q", value)
		}
	}
	for _, value := range invalid {
		if safeModulePath(value) {
			t.Fatalf("expected unsafe path: %q", value)
		}
	}
}

func TestModuleTransactionAndRollback(t *testing.T) {
	root := t.TempDir()
	staging := filepath.Join(root, "staging")
	install := filepath.Join(root, "install")
	rollback := filepath.Join(root, "rollback")
	mustWrite(t, filepath.Join(install, "existing.txt"), "old")
	mustWrite(t, filepath.Join(staging, "existing.txt"), "new")
	mustWrite(t, filepath.Join(staging, "nested", "added.txt"), "added")

	applied, err := applyModuleTransaction(staging, install, rollback)
	if err != nil {
		t.Fatal(err)
	}
	assertFile(t, filepath.Join(install, "existing.txt"), "new")
	assertFile(t, filepath.Join(install, "nested", "added.txt"), "added")
	if err := restoreModuleTransaction(applied, install, rollback); err != nil {
		t.Fatal(err)
	}
	assertFile(t, filepath.Join(install, "existing.txt"), "old")
	if _, err := os.Stat(filepath.Join(install, "nested", "added.txt")); !os.IsNotExist(err) {
		t.Fatalf("new module was not removed by rollback: %v", err)
	}
}

func TestSelectChangedModules(t *testing.T) {
	install := t.TempDir()
	mustWrite(t, filepath.Join(install, "same.txt"), "same")
	mustWrite(t, filepath.Join(install, "changed.txt"), "old")
	manifest := moduleManifest{FormatVersion: 1, Version: "9.9.9", Files: []moduleFile{
		{Path: "same.txt", SHA256: testHash("same"), Size: 4, Scope: "ui"},
		{Path: "changed.txt", SHA256: testHash("new"), Size: 3, Scope: "ui"},
	}}
	changed, fallback, err := selectChangedModules(manifest, install)
	if err != nil || fallback {
		t.Fatalf("selection failed: changed=%v fallback=%v err=%v", changed, fallback, err)
	}
	if len(changed) != 1 || changed[0].Path != "changed.txt" {
		t.Fatalf("expected only changed.txt, got %#v", changed)
	}
	manifest.Files[1].Scope = "service"
	changed, fallback, err = selectChangedModules(manifest, install)
	if err != nil || fallback || len(changed) != 1 {
		t.Fatalf("service change must remain modular: %#v %v %v", changed, fallback, err)
	}
}

func TestUpdaterChangeIsAppliedByExternalRuntimeCopy(t *testing.T) {
	install := t.TempDir()
	mustWrite(t, filepath.Join(install, "tgdesk-updater.exe"), "old")
	manifest := moduleManifest{FormatVersion: 1, Version: "9.9.9", Files: []moduleFile{
		{Path: "tgdesk-updater.exe", SHA256: testHash("new"), Size: 3, Scope: "bootstrap"},
	}}
	changed, requiresInstaller, err := selectChangedModules(manifest, install)
	if err != nil || requiresInstaller || len(changed) != 1 || changed[0].Path != "tgdesk-updater.exe" {
		t.Fatalf("updater change must remain modular: changed=%v installer=%v err=%v",
			changed, requiresInstaller, err)
	}
}

func TestReplaceStoppedUpdaterKeepsCanonicalName(t *testing.T) {
	root := t.TempDir()
	install := filepath.Join(root, "install")
	staging := filepath.Join(root, "staging")
	installed := filepath.Join(install, "tgdesk-updater.exe")
	replacement := filepath.Join(staging, "tgdesk-updater.next.exe")
	mustWrite(t, installed, "old-updater")
	mustWrite(t, replacement, "new-updater")
	if err := replaceStoppedUpdater(installed, replacement, staging); err != nil {
		t.Fatal(err)
	}
	assertFile(t, installed, "new-updater")
	if _, err := os.Stat(replacement); !os.IsNotExist(err) {
		t.Fatalf("replacement must be consumed: %v", err)
	}
	if _, err := os.Stat(filepath.Join(staging, "tgdesk-updater.previous.exe")); !os.IsNotExist(err) {
		t.Fatalf("previous updater must not remain after success: %v", err)
	}
}

func TestOfflineManifestAndStagingVerification(t *testing.T) {
	root := t.TempDir()
	files := filepath.Join(root, "files")
	mustWrite(t, filepath.Join(files, "tgdesk.exe"), "new")
	manifest := moduleManifest{FormatVersion: 1, Version: "9.9.9", Files: []moduleFile{
		{Path: "tgdesk.exe", SHA256: testHash("new"), Size: 3, Scope: "service"},
	}}
	raw, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "manifest.json"), raw, 0600); err != nil {
		t.Fatal(err)
	}
	loaded, err := readStagedManifest(filepath.Join(root, "manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := verifyStagedFiles(files, loaded); err != nil {
		t.Fatal(err)
	}
	mustWrite(t, filepath.Join(files, "tgdesk.exe"), "tampered")
	if err := verifyStagedFiles(files, loaded); err == nil {
		t.Fatal("tampered staging must be rejected")
	}
}

func TestProgressReporterPublishesMeasuredPhase(t *testing.T) {
	var received ProgressEvent
	reportProgress(func(event ProgressEvent) { received = event }, 48, "Instalando")
	if received.Percent != 48 || received.Message != "Instalando" {
		t.Fatalf("unexpected progress event: %#v", received)
	}
}

func mustWrite(t *testing.T, path, value string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(value), 0644); err != nil {
		t.Fatal(err)
	}
}

func assertFile(t *testing.T, path, expected string) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != expected {
		t.Fatalf("%s: got %q want %q", path, raw, expected)
	}
}
