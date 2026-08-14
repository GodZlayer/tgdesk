package main

import (
	"net"
	"os"
	"regexp"
	"runtime"
	"testing"
	"time"
)

// O vigia precisa ler a tabela TCP do SISTEMA corretamente — se ele mentir, o
// produto ou promete acesso que não existe (o problema atual) ou fica
// reconfigurando um acesso que está bom.
//
// O teste abre uma conexão de verdade e exige que o vigia a enxergue.
func TestVigiaEnxergaConexaoRealEstabelecida(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("a tabela TCP é lida por API do Windows")
	}

	ouvinte, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("não foi possível abrir ouvinte: %v", err)
	}
	defer ouvinte.Close()
	go func() {
		c, err := ouvinte.Accept()
		if err == nil {
			time.Sleep(2 * time.Second)
			c.Close()
		}
	}()

	porta := uint16(ouvinte.Addr().(*net.TCPAddr).Port)
	conexao, err := net.Dial("tcp", ouvinte.Addr().String())
	if err != nil {
		t.Fatalf("não foi possível conectar: %v", err)
	}
	defer conexao.Close()

	viva, err := ConexaoEstabelecidaCom("127.0.0.1", porta)
	if err != nil {
		t.Fatalf("leitura da tabela TCP falhou: %v", err)
	}
	if !viva {
		t.Fatal("conexão estabelecida de verdade não foi vista: o vigia " +
			"reconfiguraria um acesso remoto que está funcionando")
	}
}

// E o contrário: porta sem conexão nenhuma não pode parecer viva, senão o
// produto continua prometendo acesso que não existe — que é exatamente o
// defeito que o vigia veio corrigir.
func TestVigiaNaoInventaConexao(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("a tabela TCP é lida por API do Windows")
	}
	// Porta alta e improvável, sem ninguém do outro lado.
	viva, err := ConexaoEstabelecidaCom("127.0.0.1", 59987)
	if err != nil {
		t.Fatalf("leitura da tabela TCP falhou: %v", err)
	}
	if viva {
		t.Fatal("o vigia viu conexão onde não há: continuaria prometendo acesso inexistente")
	}
}

// A primeira versao do vigia checava PRESENCA de conexao. Isso nao detecta o
// defeito real: no parque havia sempre uma conexao estabelecida, mas era
// sempre uma NOVA — a porta local ia de 59254 para 58612 entre amostras.
//
// Reconectar sem parar equivale a nao estar registrado, do ponto de vista de
// quem tenta acessar. Por isso o vigia precisa devolver a IDENTIDADE da
// conexao, nao apenas se ela existe.
func TestVigiaDevolveIdentidadeDaConexao(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("a tabela TCP é lida por API do Windows")
	}
	ouvinte, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("ouvinte: %v", err)
	}
	defer ouvinte.Close()
	go func() {
		if c, err := ouvinte.Accept(); err == nil {
			time.Sleep(2 * time.Second)
			c.Close()
		}
	}()

	porta := uint16(ouvinte.Addr().(*net.TCPAddr).Port)
	conexao, err := net.Dial("tcp", ouvinte.Addr().String())
	if err != nil {
		t.Fatalf("conectar: %v", err)
	}
	defer conexao.Close()

	viva, portaLocal, err := ConexaoComPortaLocal("127.0.0.1", porta)
	if err != nil || !viva {
		t.Fatalf("conexão real não foi vista (err=%v)", err)
	}
	if portaLocal == 0 {
		t.Fatal("sem a porta local não há como saber se a conexão é a mesma de antes — " +
			"e é a troca de porta que denuncia o ciclo de reconexão")
	}
	esperada := uint16(conexao.LocalAddr().(*net.TCPAddr).Port)
	if portaLocal != esperada {
		t.Fatalf("porta local errada: %d, esperada %d", portaLocal, esperada)
	}
}

// O vigia precisa contar reconexões numa JANELA, não consecutivas.
//
// A primeira versão exigia 3 detecções seguidas e zerava o contador a cada
// verificação boa. Mas a reconexão medida no parque acontece a cada ~30-45 s e
// a verificação roda a cada 15 s, então a sequência real era:
//
//	zera · zera · conta 1 · zera · conta 1 · zera ...
//
// O contador nunca chegava a 3, e o vigia não disparou numa máquina que
// reconectava sem parar. Exigir eventos CONSECUTIVOS de um fenômeno
// intermitente é errado por construção.
func TestVigiaContaReconexoesNumaJanela(t *testing.T) {
	// A janela vive junto do estado, em vigia_registro.go — o laço só a
	// consulta. Procurá-la em control.go era procurar no lugar errado depois
	// que o estado saiu de lá.
	acumulador, err := os.ReadFile("vigia_registro.go")
	if err != nil {
		t.Fatalf("vigia_registro.go: %v", err)
	}
	if !regexp.MustCompile(`Sub\(v\.inicioDaJanela\) > janelaDeInstabilidade`).Match(acumulador) {
		t.Error("a contagem precisa ser por janela de tempo: entre duas quedas a " +
			"conexão parece boa, e zerar ali apaga o padrão")
	}

	fonte, err := os.ReadFile("control.go")
	if err != nil {
		t.Fatalf("control.go: %v", err)
	}
	// E o reset incondicional a cada verificação boa não pode voltar.
	if regexp.MustCompile(`\} else if err == nil \{\s*falhasDeRegistro = 0`).Match(fonte) {
		t.Error("o contador voltou a zerar a cada verificação boa: com reconexão " +
			"a cada 30-45s e verificação a cada 15s, ele nunca alcança o limiar")
	}
}

// O estado do vigia precisa sobreviver ao reinício do laço de controle.
//
// A ironia que o log revelou: o contador que media a instabilidade era
// destruído pela mesma instabilidade que devia medir. O túnel WireGuard era
// recriado a cada dois minutos, o laço de controle reiniciava junto, e as
// variáveis locais — contador, janela, última porta — voltavam a zero antes de
// o vigia acumular as três reconexões.
func TestEstadoDoVigiaSobreviveAoLaco(t *testing.T) {
	fonte, err := os.ReadFile("control.go")
	if err != nil {
		t.Fatalf("control.go: %v", err)
	}
	texto := string(fonte)

	// As variáveis não podem voltar a ser locais do laço.
	for _, local := range []string{"falhasDeRegistro :=", "var ultimaPortaRendezvous", "inicioDaJanela :="} {
		if regexp.MustCompile(regexp.QuoteMeta(local)).MatchString(texto) {
			t.Errorf("estado do vigia voltou a ser local do laço (%q): "+
				"ele é zerado a cada reconexão, que é justamente o que se quer medir", local)
		}
	}
	if !regexp.MustCompile(`vigiaDoRegistro\.`).MatchString(texto) {
		t.Error("o laço precisa usar o estado que vive no processo")
	}
}

// E o comportamento do acumulador: janela que expira zera, dentro da janela soma.
func TestVigiaAcumulaDentroDaJanela(t *testing.T) {
	v := &vigiaDeRegistro{inicioDaJanela: time.Now()}

	if v.viuReconexao(true, 1000) {
		t.Fatal("a primeira observação não pode contar como reconexão: não há com o que comparar")
	}
	if !v.viuReconexao(true, 2000) {
		t.Fatal("porta diferente é reconexão")
	}
	if v.viuReconexao(true, 2000) {
		t.Fatal("mesma porta não é reconexão")
	}
	if v.viuReconexao(false, 0) {
		t.Fatal("sem conexão não há troca de conexão a relatar")
	}

	if n := v.contar(); n != 1 {
		t.Fatalf("primeira contagem deu %d", n)
	}
	if n := v.contar(); n != 2 {
		t.Fatalf("segunda contagem deu %d", n)
	}

	// Janela expirada recomeça: instabilidade de ontem não condena hoje.
	v.inicioDaJanela = time.Now().Add(-2 * janelaDeInstabilidade)
	if n := v.contar(); n != 1 {
		t.Fatalf("janela expirada devia recomeçar, deu %d", n)
	}
}
