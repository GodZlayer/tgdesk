//go:build windows

package main

import (
	"encoding/binary"
	"fmt"
	"net"
	"syscall"
	"time"
	"unsafe"
)

// Vigia do acesso remoto: VERIFICAR em vez de prometer.
//
// `setupRemoteAccess` marcava `remote_ready = true` depois de abrir um socket
// TCP para o rendezvous UMA vez. Isso responde "consigo alcançar o servidor?",
// que é outra pergunta — e a resposta continua sendo sim mesmo quando o
// registro do peer cai logo depois.
//
// Foi o que aconteceu no parque: uma máquina reportando `remote_ready: true`,
// túnel de pé, respondendo a ping, e inacessível. Medido: a conexão com o
// rendezvous trocava de porta a cada 45 segundos — conectava, era derrubada,
// reconectava, em ciclo. Nos dois instantes amostrados não havia NENHUMA
// conexão estabelecida, só restos em TimeWait.
//
// A regra que este arquivo implementa: **se o programa está ativo, o acesso
// remoto está ativo.** Não por promessa — por verificação periódica e reparo
// quando a verificação falha.

const (
	// Estado ESTABLISHED na tabela TCP do Windows (MIB_TCP_STATE_ESTAB).
	tcpEstabelecido = 5
	// Reconexões numa JANELA antes de reconfigurar. Uma isolada é normal —
	// rede oscila, o servidor reinicia. Três em cinco minutos não é oscilação,
	// é ciclo.
	falhasAteReparar = 3
)

var (
	iphlpapi                = syscall.NewLazyDLL("iphlpapi.dll")
	procGetExtendedTcpTable = iphlpapi.NewProc("GetExtendedTcpTable")
)

type linhaTCP struct {
	estado      uint32
	ipLocal     uint32
	portaLocal  uint32
	ipRemoto    uint32
	portaRemota uint32
	pid         uint32
}

// ConexaoEstabelecidaCom diz se existe conexão ESTABELECIDA com host:porta.
//
// Lê a tabela TCP do sistema em vez de tentar abrir um socket novo: abrir um
// socket prova que o servidor aceita conexão, não que a NOSSA conexão está de
// pé. São perguntas diferentes, e a segunda é a que importa para "estou
// registrado?".
// Devolve também a PORTA LOCAL, e isso não é detalhe: presença de conexão não
// prova estabilidade.
//
// Foi o erro da primeira versão deste vigia. Ele perguntava "existe conexão
// agora?" — e existia, a cada instante. Só que era sempre uma conexão NOVA: a
// porta local ia de 59254 para 58612 entre duas amostras. O ciclo de
// reconexão passava despercebido justamente porque era rápido demais para
// deixar buraco.
//
// A identidade da conexão é a porta local. Se ela muda, houve reconexão.
func ConexaoEstabelecidaCom(host string, porta uint16) (bool, error) {
	viva, _, err := ConexaoComPortaLocal(host, porta)
	return viva, err
}

func ConexaoComPortaLocal(host string, porta uint16) (bool, uint16, error) {
	ip := net.ParseIP(host)
	if ip == nil {
		enderecos, err := net.LookupIP(host)
		if err != nil || len(enderecos) == 0 {
			return false, 0, err
		}
		ip = enderecos[0]
	}
	v4 := ip.To4()
	if v4 == nil {
		return false, 0, nil
	}
	alvoIP := binary.LittleEndian.Uint32(v4)

	linhas, err := tabelaTCP()
	if err != nil {
		return false, 0, err
	}
	for _, l := range linhas {
		if l.estado != tcpEstabelecido {
			continue
		}
		// A porta vem em ordem de rede nos dois bytes baixos.
		if l.ipRemoto == alvoIP && portaDaTabela(l.portaRemota) == porta {
			return true, portaDaTabela(l.portaLocal), nil
		}
	}
	return false, 0, nil
}

func portaDaTabela(bruto uint32) uint16 {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, bruto)
	return binary.BigEndian.Uint16(b[:2])
}

// tabelaTCP lê a tabela de conexões TCP IPv4 com PID.
//
// Duas chamadas: a primeira descobre o tamanho, a segunda preenche. É o
// protocolo da API, e chutar um buffer grande desperdiçaria memória numa
// função que roda a cada 15 segundos.
func tabelaTCP() ([]linhaTCP, error) {
	const (
		afInet              = 2
		tcpTableOwnerPidAll = 5
		bufferInsuficiente  = 122 // ERROR_INSUFFICIENT_BUFFER
	)

	// TENTA MAIS DE UMA VEZ, e o motivo é uma corrida real.
	//
	// A API pede duas chamadas: a primeira descobre o tamanho, a segunda
	// preenche. Entre elas, a tabela de conexões do sistema muda — e numa
	// máquina com centenas de conexões ela muda o tempo todo. Quando cresce, a
	// segunda chamada devolve ERROR_INSUFFICIENT_BUFFER de novo.
	//
	// A versão anterior tratava isso como erro definitivo. E como o chamador
	// só agia quando `err == nil`, o vigia parava de verificar em silêncio —
	// exatamente o que aconteceu no parque: três releases sem ele disparar, e
	// nenhuma pista de por quê.
	var ultimoErro error
	for tentativa := 0; tentativa < 4; tentativa++ {
		var tamanho uint32
		r, _, _ := procGetExtendedTcpTable.Call(
			0, uintptr(unsafe.Pointer(&tamanho)), 0,
			afInet, tcpTableOwnerPidAll, 0,
		)
		if tamanho == 0 {
			ultimoErro = fmt.Errorf("tamanho da tabela TCP indisponível (código %d)", r)
			continue
		}

		// Folga de 25%: pedir exatamente o tamanho medido é pedir para perder a
		// corrida na próxima linha.
		buffer := make([]byte, tamanho+tamanho/4)
		usado := uint32(len(buffer))
		r, _, chamadaErr := procGetExtendedTcpTable.Call(
			uintptr(unsafe.Pointer(&buffer[0])), uintptr(unsafe.Pointer(&usado)), 0,
			afInet, tcpTableOwnerPidAll, 0,
		)
		if r == bufferInsuficiente {
			// A tabela cresceu. Tentar de novo é o comportamento correto.
			ultimoErro = fmt.Errorf("tabela TCP cresceu durante a leitura")
			continue
		}
		if r != 0 {
			return nil, chamadaErr
		}

		quantidade := binary.LittleEndian.Uint32(buffer[0:4])
		const tamanhoLinha = 24 // MIB_TCPROW_OWNER_PID: 6 campos de 4 bytes
		linhas := make([]linhaTCP, 0, quantidade)
		for i := uint32(0); i < quantidade; i++ {
			base := 4 + i*tamanhoLinha
			if int(base)+tamanhoLinha > len(buffer) {
				break
			}
			linhas = append(linhas, linhaTCP{
				estado:      binary.LittleEndian.Uint32(buffer[base : base+4]),
				ipLocal:     binary.LittleEndian.Uint32(buffer[base+4 : base+8]),
				portaLocal:  binary.LittleEndian.Uint32(buffer[base+8 : base+12]),
				ipRemoto:    binary.LittleEndian.Uint32(buffer[base+12 : base+16]),
				portaRemota: binary.LittleEndian.Uint32(buffer[base+16 : base+20]),
				pid:         binary.LittleEndian.Uint32(buffer[base+20 : base+24]),
			})
		}
		return linhas, nil
	}
	return nil, ultimoErro
}

// Janela de contagem da instabilidade.
//
// Cinco minutos comportam ~20 verificações a 15 s. Três reconexões nesse
// intervalo descrevem o ciclo medido no parque (uma a cada 30-45 s) e não
// disparam por uma queda isolada.
const janelaDeInstabilidade = 5 * time.Minute

// Carência entre marcar o acesso como indisponível e tentar reconfigurar.
//
// O aperto de mão do WireGuard e o registro do peer levam dezenas de segundos.
// Reconfigurar por cima do que estava quase pronto destrói o progresso — e
// declarar sucesso no mesmo instante transforma o vigia num carimbo.
const carenciaDeReparo = 60 * time.Second
