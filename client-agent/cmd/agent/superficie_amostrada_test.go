package main

import (
	"os"
	"regexp"
	"testing"
)

// A varredura de superfície lia o disco INTEIRO. Em 1 TB a 341 MB/s são ~50
// minutos por máquina, toda vez que o teste completo roda — com desgaste e
// calor no computador do cliente, e estourando qualquer estimativa de duração
// que a ação única prometa.
//
// O teste olha a estrutura porque o defeito era estrutural: a função existia,
// funcionava, media certo. O errado era o QUANTO ela lia.
func TestVarreduraAmostraNaoLeODiscoInteiro(t *testing.T) {
	fonte, err := os.ReadFile("diagnostics.go")
	if err != nil {
		t.Fatalf("não foi possível ler diagnostics.go: %v", err)
	}

	// A forma antiga: avançar byte a byte até o fim do disco.
	if regexp.MustCompile(`for diskRead < disk\.Size \{`).Match(fonte) {
		t.Error("a varredura voltou a ler o disco inteiro: ~50 min por máquina, " +
			"toda vez, com desgaste no computador do cliente")
	}

	// A forma correta: saltar de amostra em amostra.
	if !regexp.MustCompile(`passo := disk\.Size / amostrasPorDisco`).Match(fonte) {
		t.Error("a varredura precisa amostrar em passos, não ler contíguo")
	}
	if !regexp.MustCompile(`file\.Seek\(int64\(posicao\), 0\)`).Match(fonte) {
		t.Error("sem seek não há amostragem: a leitura volta a ser sequencial e integral")
	}

	// ALINHAMENTO. Leitura de dispositivo fisico exige offset multiplo do
	// setor. Sem isto, TODA leitura falha — e a primeira versao da amostragem
	// produziu 225 "erros de leitura" num NVMe saudavel, o que diagnosticaria
	// disco sadio como degradado e mandaria trocar peca boa.
	if !regexp.MustCompile(`passo -= passo % uint64\(len\(buffer\)\)`).Match(fonte) {
		t.Error("o passo precisa ser truncado para multiplo do buffer, senao " +
			"todo seek cai fora do alinhamento de setor e a leitura falha")
	}
}
