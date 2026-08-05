package updatecore

import (
	"io"
	"sync"
	"time"
)

// Limite de velocidade e progresso do download da atualização.
//
// Quem manda atualizar é o servidor, e ele também diz a que velocidade: a
// banda é dele, e com fila grande uma máquina baixando a plena carga tira
// banda do atendimento que está acontecendo ao vivo. O limite chega junto da
// ordem, pelo canal de controle.
//
// O progresso sobe pelo mesmo caminho, para que a tela mostre o que está
// acontecendo sem perguntar nada a ninguém.

// Progress descreve o andamento de uma atualização em curso.
type Progress struct {
	Version         string `json:"version,omitempty"`
	TotalBytes      int64  `json:"total_bytes"`
	DownloadedBytes int64  `json:"downloaded_bytes"`
	// Velocidade instantânea observada, e o teto imposto pelo servidor quando
	// existe. Os dois aparecem para que "está lento" seja explicável.
	BytesPerSecond int64 `json:"bytes_per_second"`
	ThrottleKbps   int   `json:"throttle_kbps,omitempty"`
}

var transfer struct {
	sync.Mutex
	limitBytesPerSecond int64
	throttleKbps        int
	version             string
	total               int64
	downloaded          int64
	windowStart         time.Time
	windowBytes         int64
	observedRate        int64
	report              func(Progress)
}

// SetTransferLimit define o teto de velocidade em kbps. Zero remove o limite.
func SetTransferLimit(kbps int) {
	transfer.Lock()
	defer transfer.Unlock()
	transfer.throttleKbps = kbps
	if kbps <= 0 {
		transfer.limitBytesPerSecond = 0
		return
	}
	transfer.limitBytesPerSecond = int64(kbps) * 1024 / 8
}

// SetProgressReporter registra quem recebe o andamento. Chamado pelo agente,
// que repassa ao servidor e ao status lido pela tela.
func SetProgressReporter(report func(Progress)) {
	transfer.Lock()
	defer transfer.Unlock()
	transfer.report = report
}

// BeginTransfer zera os contadores para uma nova atualização.
func BeginTransfer(version string, totalBytes int64) {
	transfer.Lock()
	transfer.version = version
	transfer.total = totalBytes
	transfer.downloaded = 0
	transfer.windowStart = time.Now()
	transfer.windowBytes = 0
	transfer.observedRate = 0
	report, snapshot := transfer.report, currentProgressLocked()
	transfer.Unlock()
	if report != nil {
		report(snapshot)
	}
}

func currentProgressLocked() Progress {
	return Progress{
		Version:         transfer.version,
		TotalBytes:      transfer.total,
		DownloadedBytes: transfer.downloaded,
		BytesPerSecond:  transfer.observedRate,
		ThrottleKbps:    transfer.throttleKbps,
	}
}

// throttledReader segura a leitura para respeitar o teto e contabiliza o que
// passou. O controle é feito na leitura, não na escrita, porque é a leitura
// que consome a banda do servidor.
type throttledReader struct {
	inner io.Reader
	last  time.Time
}

func newThrottledReader(inner io.Reader) io.Reader {
	return &throttledReader{inner: inner, last: time.Now()}
}

func (t *throttledReader) Read(p []byte) (int, error) {
	// Lê em pedaços pequenos quando há limite: dormir por bloco grande faria
	// a velocidade oscilar entre rajada e pausa em vez de ficar estável.
	transfer.Lock()
	limit := transfer.limitBytesPerSecond
	transfer.Unlock()
	if limit > 0 {
		chunk := limit / 10
		if chunk < 4096 {
			chunk = 4096
		}
		if int64(len(p)) > chunk {
			p = p[:chunk]
		}
	}
	n, err := t.inner.Read(p)
	if n > 0 {
		t.account(int64(n), limit)
	}
	return n, err
}

func (t *throttledReader) account(n, limit int64) {
	transfer.Lock()
	transfer.downloaded += n
	transfer.windowBytes += n
	elapsed := time.Since(transfer.windowStart)
	if elapsed >= time.Second {
		transfer.observedRate = int64(float64(transfer.windowBytes) / elapsed.Seconds())
		transfer.windowStart = time.Now()
		transfer.windowBytes = 0
	}
	report, snapshot := transfer.report, currentProgressLocked()
	transfer.Unlock()
	if report != nil {
		report(snapshot)
	}
	if limit <= 0 {
		return
	}
	// Espera o tempo que este pedaço "deveria" ter levado no teto imposto.
	expected := time.Duration(float64(n) / float64(limit) * float64(time.Second))
	if spent := time.Since(t.last); expected > spent {
		time.Sleep(expected - spent)
	}
	t.last = time.Now()
}
