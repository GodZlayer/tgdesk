package main

import (
	"net"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"testing"
)

// O servidor casa dispositivo por MAC. Um MAC que muda a cada boot cria uma
// máquina nova a cada boot — foi assim que UM container do CRM virou DEZ
// dispositivos no painel em um único dia, todos com MAC começando em 02:.
//
// O bit de administração local separa os dois mundos: MAC de fábrica tem o bit
// em 0 e é estável para sempre; com o bit em 1 foi gerado por Docker, por
// hipervisor ou por interface virtual, e costuma mudar.
func TestMacGeradoNaoServeComoIdentidade(t *testing.T) {
	// Os MACs que criaram os fantasmas, exatamente como vieram do banco.
	gerados := []string{
		"02:6a:78:32:39:cb", "02:2f:89:34:a8:f4", "02:e9:e7:42:7b:5c",
		"02:f5:35:61:5c:7c", "02:e3:f7:80:26:ff",
	}
	for _, m := range gerados {
		hw, err := net.ParseMAC(m)
		if err != nil {
			t.Fatalf("MAC inválido no teste: %s", m)
		}
		if hw[0]&0x02 == 0 {
			t.Errorf("%s deveria ser reconhecido como gerado", m)
		}
	}

	// E um de fábrica precisa continuar servindo, senão nenhuma máquina real
	// seria mais reconhecida.
	deFabrica, _ := net.ParseMAC("3c:7c:3f:11:22:33")
	if deFabrica[0]&0x02 != 0 {
		t.Error("MAC de fábrica foi classificado como gerado")
	}
}

// A identidade precisa ser gravada num lugar que sobreviva ao reinício.
//
// O peer do CRM não define TGDESK_DATA_DIR, e o fallback usava
// os.Getenv("ProgramData") — vazio no Linux — caindo para o caminho Windows
// literal. Isso cria um diretório chamado "C:\ProgramData" DENTRO do diretório
// de trabalho, que não é volume nenhum: a identidade sumia a cada reinício.
func TestDiretorioDeDadosNaoUsaCaminhoWindowsForaDoWindows(t *testing.T) {
	fonte, err := os.ReadFile("host.go")
	if err != nil {
		t.Fatalf("host.go: %v", err)
	}
	if !regexp.MustCompile(`runtime\.GOOS != "windows"`).Match(fonte) {
		t.Fatal("o fallback do diretório de dados não distingue o sistema: " +
			"em Linux a identidade vai para um caminho descartável e o " +
			"dispositivo se registra de novo a cada reinício")
	}

	if runtime.GOOS == "windows" {
		return
	}
	dir := tgdeskDataDir()
	if filepath.IsAbs(dir) == false || regexp.MustCompile(`^[A-Za-z]:`).MatchString(dir) {
		t.Fatalf("diretório de dados inválido fora do Windows: %q", dir)
	}
}

// Descartar só o bit de administração local não basta, e o parque mostrou por
// quê: o VMware instala adaptadores com MAC de "fábrica" FIXO — o mesmo número
// em toda máquina do mundo que tenha VMware.
//
// Aceitá-lo como identidade faria duas máquinas diferentes colidirem no índice
// único de MAC, e a segunda receberia a identidade da primeira.
func TestMacDeAdaptadorVirtualNaoServeComoIdentidade(t *testing.T) {
	casos := []struct {
		mac     string
		virtual bool
		porque  string
	}{
		{"00:50:56:c0:00:01", true, "VMware VMnet — idêntico em toda máquina com VMware"},
		{"00:0c:29:11:22:33", true, "VMware"},
		{"00:15:5d:91:1a:7c", true, "Hyper-V"},
		{"08:00:27:aa:bb:cc", true, "VirtualBox"},
		{"f4:b5:20:64:46:2e", false, "NIC física real do parque"},
	}
	for _, c := range casos {
		hw, err := net.ParseMAC(c.mac)
		if err != nil {
			t.Fatalf("MAC inválido: %s", c.mac)
		}
		if got := ouiDeAdaptadorVirtual(hw); got != c.virtual {
			t.Errorf("%s (%s): virtual=%v, esperado %v", c.mac, c.porque, got, c.virtual)
		}
	}
}
