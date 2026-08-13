package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSpoolSobreviveSemConexao(t *testing.T) {
	// O ponto do spool: a máquina SEM internet é justamente a que costuma estar
	// com problema. Antes, o buraco no histórico coincidia com o período que
	// mais interessa.
	s := novoSpool(t.TempDir())
	defer s.Fechar()

	for i := 0; i < 50; i++ {
		s.Gravar("hardware", map[string]any{"cpu": i})
	}
	if !strings.Contains(s.Estado(), "arquivo") {
		t.Fatalf("estado inesperado: %s", s.Estado())
	}
}

func TestArquivoDaHoraCorrenteNaoEEntregue(t *testing.T) {
	// Ele está aberto para escrita: ler dele agora arriscaria pegar uma linha
	// pela metade e entregar amostra corrompida como se fosse medida.
	s := novoSpool(t.TempDir())
	defer s.Fechar()
	s.Gravar("hardware", map[string]any{"cpu": 1})

	lote, origem, _ := s.LotePendente()
	if len(lote) != 0 || origem != "" {
		t.Fatal("o arquivo aberto para escrita foi oferecido para entrega")
	}
}

func TestLoteSoSaiDoSpoolDepoisDeConfirmado(t *testing.T) {
	// É esta ordem que faz uma queda de conexão custar REENVIO e nunca perda.
	dir := t.TempDir()
	s := novoSpool(dir)
	defer s.Fechar()

	// Arquivo de uma hora passada, fechado — elegível para entrega.
	antigo := filepath.Join(dir, "spool", "2020-01-01T00.jsonl")
	linha, _ := json.Marshal(amostraLocal{Tipo: "hardware", Dados: json.RawMessage(`{"cpu":9}`)})
	if err := os.WriteFile(antigo, append(linha, '\n'), 0600); err != nil {
		t.Fatal(err)
	}

	lote, origem, _ := s.LotePendente()
	if len(lote) != 1 {
		t.Fatalf("esperava 1 amostra, veio %d", len(lote))
	}
	if _, err := os.Stat(antigo); err != nil {
		t.Fatal("o arquivo sumiu antes da confirmação: uma queda de conexão perderia o dado")
	}

	s.ConfirmarEntrega(origem)
	if _, err := os.Stat(antigo); err == nil {
		t.Fatal("o arquivo permaneceu depois de confirmado: o mesmo dado subiria para sempre")
	}
}

func TestLinhaCorrompidaNaoDerrubaOArquivo(t *testing.T) {
	// Queda de energia no meio de uma escrita deixa meia linha. Perder uma
	// amostra é barato; perder a hora inteira não.
	dir := t.TempDir()
	s := novoSpool(dir)
	defer s.Fechar()

	boa, _ := json.Marshal(amostraLocal{Tipo: "hardware", Dados: json.RawMessage(`{"cpu":1}`)})
	conteudo := append([]byte("{lixo pela metade\n"), append(boa, '\n')...)
	if err := os.WriteFile(filepath.Join(dir, "spool", "2020-01-01T00.jsonl"), conteudo, 0600); err != nil {
		t.Fatal(err)
	}

	lote, _, _ := s.LotePendente()
	if len(lote) != 1 {
		t.Fatalf("a linha boa devia sobreviver à corrompida; vieram %d", len(lote))
	}
}

func TestSpoolNuncaEncheODisco(t *testing.T) {
	// Seria o cúmulo: um produto que diagnostica disco cheio enchendo o disco.
	dir := t.TempDir()
	s := novoSpool(dir)
	defer s.Fechar()
	s.tetoMB = 0 // qualquer coisa já estoura

	grande := strings.Repeat("x", 4096)
	for i := 0; i < 5; i++ {
		linha, _ := json.Marshal(amostraLocal{Tipo: "t", Dados: json.RawMessage(`"` + grande + `"`)})
		os.WriteFile(filepath.Join(dir, "spool", "2020-01-0"+string(rune('1'+i))+"T00.jsonl"),
			append(linha, '\n'), 0600)
	}
	s.Gravar("hardware", map[string]any{"cpu": 1})

	arquivos, _ := s.listarLocked()
	if len(arquivos) > 2 {
		t.Fatalf("a poda não segurou o teto: sobraram %d arquivos", len(arquivos))
	}
}
