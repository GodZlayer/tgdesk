package main

import (
	"net"
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
