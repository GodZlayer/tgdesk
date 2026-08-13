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
