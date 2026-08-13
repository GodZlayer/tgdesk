package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// Telemetria local com entrega diferida (store-and-forward).
//
// O problema que isto resolve: até aqui, a telemetria só existia se houvesse
// conexão no instante da coleta. Máquina sem internet não media nada — e a
// máquina sem internet é justamente a que costuma estar com problema. O buraco
// no histórico coincidia com o período que mais interessa.
//
// Agora a coleta é LOCAL e a entrega é oportunista: o agente grava em disco,
// e quando o canal está de pé ele drena. Se a internet cair por um dia, o dia
// inteiro sobe depois, com o carimbo de quando foi COLETADO — nunca de quando
// foi entregue, senão a linha do tempo mentiria.
//
// Três decisões que definem o custo, e o custo é o requisito:
//
//  1. ARQUIVO POR HORA, append-only. Escrever é seek para o fim e uma linha;
//     não há leitura, índice, nem reescrita. Rotacionar por hora dá granulidade
//     de expurgo sem precisar varrer conteúdo.
//  2. TETO EM DISCO. Acima do limite, o arquivo MAIS ANTIGO é apagado. O agente
//     nunca é o motivo de um disco encher — que seria o cúmulo, num produto que
//     diagnostica disco cheio.
//  3. DRENO EM LOTE, com confirmação. A linha só é descartada depois que o
//     servidor aceitou o lote. Descartar no envio perderia dado em toda queda
//     de conexão, que é exatamente o cenário que este arquivo existe para
//     cobrir.
type spoolTelemetria struct {
	dir       string
	mu        sync.Mutex
	tetoMB    int64
	maxLote   int
	arquivo   *os.File
	horaAtual string
}

const (
	// Teto do spool em disco. 64 MB comporta semanas de amostra a cada 30 s e
	// é irrelevante em qualquer máquina que rode Windows.
	spoolTetoMB = 64
	// Linhas por lote de entrega. Grande o bastante para não conversar demais,
	// pequeno o bastante para caber numa mensagem de WebSocket sem susto.
	spoolMaxLote = 200
)

// amostraLocal é uma linha do spool.
//
// `Em` é o instante da COLETA, e é ele que vale para sempre. O servidor nunca
// usa a hora de chegada: um lote que subiu depois de um dia offline
// descreveria um dia inteiro comprimido em um segundo.
type amostraLocal struct {
	Em    time.Time       `json:"em"`
	Tipo  string          `json:"tipo"`
	Dados json.RawMessage `json:"dados"`
}

func novoSpool(dir string) *spoolTelemetria {
	caminho := filepath.Join(dir, "spool")
	_ = os.MkdirAll(caminho, 0700)
	return &spoolTelemetria{dir: caminho, tetoMB: spoolTetoMB, maxLote: spoolMaxLote}
}

// Gravar acrescenta uma amostra ao spool da hora corrente.
//
// Falha de escrita NÃO é fatal e não interrompe nada: telemetria é melhor-
// esforço, e um agente que morre porque não conseguiu gravar métrica seria
// pior que a métrica perdida.
func (s *spoolTelemetria) Gravar(tipo string, dados any) {
	bruto, err := json.Marshal(dados)
	if err != nil {
		return
	}
	linha, err := json.Marshal(amostraLocal{
		Em: time.Now().UTC(), Tipo: tipo, Dados: bruto,
	})
	if err != nil {
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if err := s.abrirDaHoraLocked(); err != nil {
		return
	}
	_, _ = s.arquivo.Write(append(linha, '\n'))
	s.podarLocked()
}

func (s *spoolTelemetria) abrirDaHoraLocked() error {
	hora := time.Now().UTC().Format("2006-01-02T15")
	if s.arquivo != nil && s.horaAtual == hora {
		return nil
	}
	if s.arquivo != nil {
		_ = s.arquivo.Close()
		s.arquivo = nil
	}
	f, err := os.OpenFile(
		filepath.Join(s.dir, hora+".jsonl"),
		os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	s.arquivo, s.horaAtual = f, hora
	return nil
}

// podarLocked apaga os arquivos mais antigos até caber no teto.
//
// Descartar o ANTIGO e não o novo é deliberado: num diagnóstico, o dado
// recente explica o que está acontecendo agora, e o antigo já teve chance de
// ser entregue. Descartar o novo protegeria o histórico às custas do presente.
func (s *spoolTelemetria) podarLocked() {
	arquivos, total := s.listarLocked()
	limite := s.tetoMB * 1024 * 1024
	for total > limite && len(arquivos) > 1 {
		mais := arquivos[0]
		if info, err := os.Stat(mais); err == nil {
			total -= info.Size()
		}
		_ = os.Remove(mais)
		arquivos = arquivos[1:]
	}
}

func (s *spoolTelemetria) listarLocked() ([]string, int64) {
	entradas, err := os.ReadDir(s.dir)
	if err != nil {
		return nil, 0
	}
	var arquivos []string
	var total int64
	for _, e := range entradas {
		if e.IsDir() || filepath.Ext(e.Name()) != ".jsonl" {
			continue
		}
		arquivos = append(arquivos, filepath.Join(s.dir, e.Name()))
		if info, err := e.Info(); err == nil {
			total += info.Size()
		}
	}
	// O nome é a hora em ISO, então ordem alfabética é ordem cronológica.
	sort.Strings(arquivos)
	return arquivos, total
}

// LotePendente devolve o próximo lote a entregar, e o arquivo de onde saiu.
//
// Devolve o arquivo junto porque a confirmação é por arquivo: só se remove
// depois que o servidor aceitou, e só o arquivo inteiramente entregue. Um lote
// parcial deixa o arquivo onde está e a próxima passagem recomeça dele.
func (s *spoolTelemetria) LotePendente() (lote []amostraLocal, origem string, completo bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	arquivos, _ := s.listarLocked()
	for _, caminho := range arquivos {
		// O arquivo da hora corrente ainda está aberto para escrita. Entregar
		// dele agora arriscaria ler uma linha pela metade — ele espera a
		// virada da hora, que é no máximo 60 min.
		if s.arquivo != nil && caminho == filepath.Join(s.dir, s.horaAtual+".jsonl") {
			continue
		}
		f, err := os.Open(caminho)
		if err != nil {
			continue
		}
		leitor := bufio.NewScanner(f)
		leitor.Buffer(make([]byte, 0, 64*1024), 1024*1024)
		for leitor.Scan() && len(lote) < s.maxLote {
			var a amostraLocal
			// Linha corrompida (queda de energia no meio da escrita) é pulada,
			// não aborta o lote: perder uma amostra é barato, perder o arquivo
			// inteiro não.
			if json.Unmarshal(leitor.Bytes(), &a) == nil {
				lote = append(lote, a)
			}
		}
		completo = !leitor.Scan()
		_ = f.Close()
		if len(lote) > 0 {
			return lote, caminho, completo
		}
		// Arquivo vazio ou só com lixo: não há o que entregar dele.
		_ = os.Remove(caminho)
	}
	return nil, "", false
}

// ConfirmarEntrega remove o arquivo já aceito pelo servidor.
//
// Chamado SÓ depois do aceite. É esta ordem que garante que uma queda de
// conexão custa reenvio, nunca perda.
func (s *spoolTelemetria) ConfirmarEntrega(origem string) {
	if origem == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_ = os.Remove(origem)
}

// Estado descreve o spool, para o status local e para depuração.
func (s *spoolTelemetria) Estado() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	arquivos, total := s.listarLocked()
	return fmt.Sprintf("%d arquivo(s), %.1f MB pendentes", len(arquivos),
		float64(total)/(1024*1024))
}

func (s *spoolTelemetria) Fechar() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.arquivo != nil {
		_ = s.arquivo.Close()
		s.arquivo = nil
	}
}
