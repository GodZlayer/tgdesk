package main

import (
	"sync"
	"time"
)

// Estado do vigia de registro, VIVO ALÉM DO LAÇO DE CONTROLE.
//
// A versão anterior guardava contador, janela e última porta como variáveis
// locais do laço. Parecia natural — e era exatamente o que impedia o vigia de
// funcionar.
//
// O log do agente mostrou por quê: o túnel WireGuard era destruído e recriado a
// cada dois minutos, e o laço de controle reinicia junto (a conexão morre com o
// adaptador). A cada reinício o contador voltava a zero, a janela recomeçava e
// a última porta se perdia. O vigia nunca acumulava três reconexões porque ele
// próprio era reiniciado antes disso.
//
// A ironia importa e vale registrar: o estado que media a instabilidade era
// destruído pela mesma instabilidade que devia medir.
//
// Por isso vive no processo. O laço vai e volta; a observação fica.
type vigiaDeRegistro struct {
	mu             sync.Mutex
	ultimaPorta    uint16
	reconexoes     int
	inicioDaJanela time.Time
}

var vigiaDoRegistro = &vigiaDeRegistro{inicioDaJanela: time.Now()}

// viuReconexao registra a observação e diz se houve troca de conexão.
//
// A identidade da conexão é a porta local: presença não prova estabilidade,
// porque a cada instante existe UMA conexão — só que é sempre uma nova.
func (v *vigiaDeRegistro) viuReconexao(viva bool, porta uint16) bool {
	v.mu.Lock()
	defer v.mu.Unlock()
	if !viva {
		return false
	}
	trocou := v.ultimaPorta != 0 && porta != v.ultimaPorta
	v.ultimaPorta = porta
	return trocou
}

// contar acumula uma falha na janela corrente e devolve o total.
func (v *vigiaDeRegistro) contar() int {
	v.mu.Lock()
	defer v.mu.Unlock()
	if agora := time.Now(); agora.Sub(v.inicioDaJanela) > janelaDeInstabilidade {
		v.inicioDaJanela, v.reconexoes = agora, 0
	}
	v.reconexoes++
	return v.reconexoes
}

func (v *vigiaDeRegistro) zerar() {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.ultimaPorta, v.reconexoes, v.inicioDaJanela = 0, 0, time.Now()
}
