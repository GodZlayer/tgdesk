package handlers

import (
	"context"
	"sync"
	"time"
)

// Leitor dos parâmetros de diagnóstico (§18 da arquitetura).
//
// A invariante é que NENHUM limiar mora no código: degrau, temperatura de
// parada, limiar de alerta e ECE de promoção vivem em `diag_param`, versionados,
// e a versão vigente acompanha o que for gravado. Este arquivo é o único ponto
// do api-core que lê aquela tabela.
//
// Por que um cache e não uma consulta por uso: o detector de trava consulta o
// limiar de buraco a cada tick de 250ms, por dispositivo conectado. Consultar o
// banco nessa cadência seria transformar configuração em carga.
//
// Por que o cache expira em vez de viver para sempre: trocar de versão vigente
// tem que surtir efeito sem reiniciar o servidor. 30s é o atraso máximo entre
// promover uma versão e ela valer.

type diagParams struct {
	versao  string
	valores map[string]float64
}

var (
	diagParamMu     sync.RWMutex
	diagParamCache  *diagParams
	diagParamCarreg time.Time
)

const diagParamTTL = 30 * time.Second

// diagParamSet devolve o conjunto vigente. Nunca devolve nil: se o banco não
// responder, entrega o último conjunto conhecido, e só entrega vazio se nunca
// houve leitura bem-sucedida — caso em que quem chama cai no default declarado
// em diagParam.
func (s *Server) diagParamSet(ctx context.Context) *diagParams {
	diagParamMu.RLock()
	cache, carregado := diagParamCache, diagParamCarreg
	diagParamMu.RUnlock()
	if cache != nil && time.Since(carregado) < diagParamTTL {
		return cache
	}

	rows, err := s.Pool.Query(ctx, `
		SELECT p.versao, p.chave, p.valor
		FROM diag_param p
		JOIN diag_param_set s ON s.versao = p.versao
		WHERE s.vigente`)
	if err != nil {
		if cache != nil {
			return cache
		}
		return &diagParams{valores: map[string]float64{}}
	}
	defer rows.Close()

	novo := &diagParams{valores: map[string]float64{}}
	for rows.Next() {
		var versao, chave string
		var valor float64
		if rows.Scan(&versao, &chave, &valor) != nil {
			continue
		}
		novo.versao = versao
		novo.valores[chave] = valor
	}
	// Conjunto vazio não substitui um conjunto bom: seria trocar configuração
	// real por silêncio de banco.
	if len(novo.valores) == 0 && cache != nil {
		return cache
	}
	diagParamMu.Lock()
	diagParamCache, diagParamCarreg = novo, time.Now()
	diagParamMu.Unlock()
	return novo
}

// diagParam lê um limiar pelo nome. O default existe para o caso de a chave
// ainda não ter sido semeada — nunca para substituir a tabela em operação
// normal, e por isso todo chamador passa o mesmo valor que está na §18.
func (s *Server) diagParam(ctx context.Context, chave string, padrao float64) float64 {
	if v, ok := s.diagParamSet(ctx).valores[chave]; ok {
		return v
	}
	return padrao
}

// diagParamVersao é o que acompanha o dado gravado. Sem ele, dois registros
// feitos sob limiares diferentes seriam comparados como se fossem iguais.
func (s *Server) diagParamVersao(ctx context.Context) string {
	return s.diagParamSet(ctx).versao
}
