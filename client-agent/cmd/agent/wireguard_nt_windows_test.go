//go:build windows

package main

import (
	"os"
	"path/filepath"
	"testing"
)

// TestExtractTGDeskVPNDLL verifica que a DLL WireGuardNT embutida via
// //go:embed é gravada no diretório oculto esperado (ProgramData\TGDesk\bin,
// ou TGDESK_DATA_DIR\bin quando configurado) com o conteúdo correto, sem
// depender do WireGuard realmente conectar.
func TestExtractTGDeskVPNDLL(t *testing.T) {
	tmpDataDir := t.TempDir()
	t.Setenv("TGDESK_DATA_DIR", tmpDataDir)

	dest, err := extractTGDeskVPNDLL()
	if err != nil {
		t.Fatalf("extractTGDeskVPNDLL falhou: %v", err)
	}

	wantDest := filepath.Join(tmpDataDir, "bin", "tgdeskvpn.dll")
	if dest != wantDest {
		t.Fatalf("caminho extraído = %q, esperado %q", dest, wantDest)
	}

	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("ler arquivo extraído: %v", err)
	}
	if len(got) != len(tgdeskvpnDLL) {
		t.Fatalf("tamanho extraído = %d bytes, esperado %d bytes", len(got), len(tgdeskvpnDLL))
	}
	for i := range got {
		if got[i] != tgdeskvpnDLL[i] {
			t.Fatalf("conteúdo extraído difere dos bytes embutidos no offset %d", i)
		}
	}

	// Chamar de novo deve ser idempotente (mesmo tamanho => pula rewrite) e
	// continuar retornando o mesmo caminho/conteúdo.
	dest2, err := extractTGDeskVPNDLL()
	if err != nil {
		t.Fatalf("segunda chamada de extractTGDeskVPNDLL falhou: %v", err)
	}
	if dest2 != dest {
		t.Fatalf("segunda chamada retornou caminho diferente: %q vs %q", dest2, dest)
	}
}

func TestWireGuardNTHiddenDir(t *testing.T) {
	t.Setenv("TGDESK_DATA_DIR", `C:\custom\data`)
	if got, want := wireGuardNTHiddenDir(), filepath.Join(`C:\custom\data`, "bin"); got != want {
		t.Fatalf("wireGuardNTHiddenDir com TGDESK_DATA_DIR = %q, esperado %q", got, want)
	}

	t.Setenv("TGDESK_DATA_DIR", "")
	t.Setenv("ProgramData", `C:\ProgramData`)
	if got, want := wireGuardNTHiddenDir(), filepath.Join(`C:\ProgramData`, "TGDesk", "bin"); got != want {
		t.Fatalf("wireGuardNTHiddenDir padrão = %q, esperado %q", got, want)
	}
}
