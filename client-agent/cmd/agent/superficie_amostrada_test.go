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

// Com amostragem, CADA leitura é uma região. A condicao antiga esperava
// acumular bytes lidos suficientes para fechar uma regiao — o que so fazia
// sentido na varredura contigua. Amostrando, ela nunca era atingida e o teste
// devolvia 2 regioes em vez de 240.
//
// Duas regioes nao tem cauda: e a cauda (p99 contra mediana) que separa disco
// que PARA de disco lento, e sem ela o diagnostico perde justamente o sinal
// que o usuario relata.
func TestCadaAmostraEUmaRegiao(t *testing.T) {
	fonte, err := os.ReadFile("diagnostics.go")
	if err != nil {
		t.Fatalf("não foi possível ler diagnostics.go: %v", err)
	}
	if regexp.MustCompile(`diskRead-regionStart >= regionSize`).Match(fonte) {
		t.Error("a condição de fechar região voltou a ser a da varredura contígua: " +
			"amostrando, ela nunca é atingida e sobram 2 regiões")
	}
	if !regexp.MustCompile(`if regionBytes > 0 \{\n\s+flushRegion\(\)`).Match(fonte) {
		t.Error("cada amostra precisa fechar sua própria região")
	}
}

// O campo `offset` de cada região precisa ser a POSIÇÃO NO DISCO.
//
// Ele recebia `diskRead`, o total de bytes lidos. Na varredura contígua isso
// dava no mesmo; com amostragem, não: 240 leituras de 8 MB num disco de 240 GB
// produzem offsets de 0 a 1,9 GB, todos apontando para o começo do disco.
//
// O custo foi real. Analisando uma varredura por esse campo eu "descobri" uma
// região degradada no meio do disco da Dani, com leituras de 37 segundos, e
// quase troquei um laudo correto — sem defeito físico — por um que mandaria
// trocar um disco saudável. Repetir a medição refutou; o campo errado é que
// tinha criado o padrão.
func TestOffsetDaRegiaoEPosicaoNoDiscoNaoBytesLidos(t *testing.T) {
	fonte, err := os.ReadFile("diagnostics.go")
	if err != nil {
		t.Fatalf("diagnostics.go: %v", err)
	}
	texto := string(fonte)

	if regexp.MustCompile(`regionStart\s*=\s*diskRead`).MatchString(texto) {
		t.Error("`offset` voltou a receber bytes lidos em vez da posição no disco: " +
			"a curva de velocidade por posição vira ficção, e é ela que separa " +
			"'uma região ruim' de 'o disco inteiro engasgando'")
	}
	if !regexp.MustCompile(`regionStart\s*=\s*posicao`).MatchString(texto) {
		t.Error("nenhuma atribuição de posição real ao início da região: " +
			"sem isso o resultado não sustenta leitura posicional")
	}
}

// A varredura precisa visitar as regiões FORA DE ORDEM.
//
// Varrer do começo ao fim faz tempo e espaço andarem juntos: carga concorrente
// durante um trecho do exame vira, no relatório, uma "região ruim" do disco.
// Foi assim que uma varredura do parque produziu um miolo lento com leituras
// de 37 segundos — padrão convincente e falso, que não reapareceu na repetição.
//
// Embaralhar quebra a correlação. Zona ruim de verdade continua agrupada.
func TestVarreduraVisitaRegioesForaDeOrdem(t *testing.T) {
	fonte, err := os.ReadFile("diagnostics.go")
	if err != nil {
		t.Fatalf("diagnostics.go: %v", err)
	}
	if !regexp.MustCompile(`embaralharPosicoes\(posicoes\)`).MatchString(string(fonte)) {
		t.Error("a varredura voltou a ser sequencial: carga concorrente vai " +
			"reaparecer como região ruim, e o laudo manda trocar disco saudável")
	}
}
