package main

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// DIAGNÓSTICO NÃO ALTERA A MÁQUINA. Nunca, de forma nenhuma.
//
// A regra é do dono do produto e é absoluta: nenhum teste pode limpar,
// remover, reparar ou modificar coisa alguma no computador do cliente — nem
// cache, nem arquivo temporário, nem "lixo". Medir e consertar são atos
// diferentes, e misturá-los destrói a única coisa que o exame tem a oferecer:
// a certeza de que o estado observado é o estado real, não o estado depois de
// uma faxina que ninguém pediu.
//
// Há três razões práticas, além da regra:
//
//  1. Um exame que altera não é REPETÍVEL. A segunda execução mede uma máquina
//     diferente da primeira, e a comparação antes/depois — que é como §11.6
//     valida um reparo — perde o sentido.
//  2. Alterar sem pedir é dano. "Arquivo lixo" é julgamento nosso sobre o
//     arquivo de outra pessoa, e o Defender colocando algo em quarentena pode
//     derrubar um sistema inteiro que dependia daquilo.
//  3. Se o exame conserta em silêncio, o diagnóstico fica errado: o problema
//     some, a causa não é registrada, e o mesmo defeito volta sem histórico.
//
// Este teste existe porque a auditoria manual encontrou `Start-MpScan` no
// catálogo — uma varredura do Defender que REMOVE ou põe em quarentena o que
// encontra. Estava lá desde sempre, num teste chamado "verificação rápida".
func TestNenhumTesteAlteraAMaquina(t *testing.T) {
	fonte, err := os.ReadFile("diagnostics.go")
	if err != nil {
		t.Fatalf("não foi possível ler diagnostics.go: %v", err)
	}
	texto := string(fonte)

	// Cada entrada é um comando que MODIFICA, com o motivo de estar proibido.
	// A lista é de negação explícita: é mais fácil auditar uma lista de
	// proibições nomeadas do que confiar que ninguém vai escrever a coisa
	// errada.
	proibidos := []struct {
		padrao string
		porque string
	}{
		{`Start-MpScan`, "varredura do Defender remove ou põe arquivos em quarentena"},
		{`Remove-MpThreat`, "remove ameaças — é apagar arquivo do cliente"},
		{`/RestoreHealth`, "DISM RestoreHealth REPARA a imagem do Windows"},
		{`sfc\s*/scannow`, "sfc /scannow repara arquivos de sistema"},
		{`-SpotFix`, "Repair-Volume -SpotFix corrige o sistema de arquivos"},
		{`-OfflineScanAndFix`, "Repair-Volume corrige o sistema de arquivos"},
		{`chkdsk[^"']*\s/f`, "chkdsk /f grava correções no sistema de arquivos"},
		{`chkdsk[^"']*\s/r`, "chkdsk /r realoca setores — altera o disco"},
		{`cleanmgr`, "limpeza de disco apaga arquivos do cliente"},
		{`Optimize-Volume`, "desfragmenta e faz TRIM — altera o disco"},
		{`Clear-RecycleBin`, "esvazia a lixeira do cliente"},
		{`Clear-DnsClientCache`, "limpa cache — alteração sem pedido"},
		{`Reset-`, "cmdlets Reset-* revertem configuração do cliente"},
		{`Restart-Computer`, "reiniciar é intervenção, não medição"},
		{`Stop-Service`, "parar serviço muda o estado da máquina"},
		{`Set-MpPreference`, "altera a configuração do antivírus"},
		{`format\s`, "formatar destrói dados"},
		{`badblocks-write`, "escrita destrutiva de superfície apaga o disco"},
	}

	for _, p := range proibidos {
		re := regexp.MustCompile(`(?i)` + p.padrao)
		for _, linha := range strings.Split(texto, "\n") {
			// Comentário citando o comando proibido para explicar por que ele
			// NÃO está aqui é justamente o que se quer incentivar.
			limpa := strings.TrimSpace(linha)
			if strings.HasPrefix(limpa, "//") {
				continue
			}
			if re.MatchString(linha) {
				t.Errorf("comando que ALTERA a máquina no catálogo de diagnóstico: %s\n"+
					"  motivo: %s\n  linha: %s", p.padrao, p.porque, limpa)
			}
		}
	}
}

// As duas ferramentas mais perigosas do catálogo são seguras APENAS pelo
// argumento que recebem. `Repair-Volume` repara; com `-Scan` só olha. `dism
// /Cleanup-Image` repara; com `/ScanHealth` só olha.
//
// Trocar uma palavra transforma exame em intervenção, e o nome do cmdlet não
// avisa — pelo contrário, ele promete reparo. Este teste prende o argumento.
func TestFerramentasDeReparoRodamSomenteEmModoDeLeitura(t *testing.T) {
	fonte, err := os.ReadFile("diagnostics.go")
	if err != nil {
		t.Fatalf("não foi possível ler diagnostics.go: %v", err)
	}
	texto := string(fonte)

	if strings.Contains(texto, "Repair-Volume") &&
		!regexp.MustCompile(`Repair-Volume[^;]*-Scan\b`).MatchString(texto) {
		t.Error("Repair-Volume sem -Scan: o cmdlet passa a CORRIGIR o sistema de arquivos")
	}
	if strings.Contains(texto, "/Cleanup-Image") &&
		!strings.Contains(texto, "/ScanHealth") {
		t.Error("DISM /Cleanup-Image sem /ScanHealth: passa a REPARAR a imagem do Windows")
	}
}

// A única escrita tolerada é o arquivo que o próprio teste cria para medir
// velocidade, no diretório temporário, removido em seguida. Isso não é limpar
// a máquina: é não deixar sujeira própria para trás.
//
// Mas escrever num disco quase cheio é risco real — e as duas máquinas do
// parque estão em 93% e 99%. O teste precisa desistir em vez de piorar a
// situação que ele foi chamado para diagnosticar.
func TestEscritaDeMedicaoRespeitaEspacoLivre(t *testing.T) {
	fonte, err := os.ReadFile("diagnostics.go")
	if err != nil {
		t.Fatalf("não foi possível ler diagnostics.go: %v", err)
	}
	texto := string(fonte)

	if !strings.Contains(texto, "espacoLivreSuficiente") {
		t.Error("o teste de escrita precisa verificar espaço livre antes de gravar: " +
			"escrever 128 MB num disco a 99% agrava o problema que se foi medir")
	}
	// E o arquivo criado precisa ser removido — sujeira própria é
	// responsabilidade nossa.
	if !regexp.MustCompile(`defer os\.Remove\(path\)`).MatchString(texto) {
		t.Error("o arquivo temporário de medição precisa ser removido")
	}
}
