package handlers

import (
	"context"
	"log"
	"time"
)

// StartSessionIsolationReconciler mantém as rotas diretas da VPN alinhadas com
// o pertencimento a subredes.
//
// A regra é única: dois participantes só se alcançam diretamente quando
// compartilham uma subrede não isolada. Sessão de acesso remoto não é exceção —
// é uma subrede temporária, criada no aceite e apagada no fechamento.
//
// A reconciliação recalcula o conjunto inteiro a cada passada, em vez de abrir
// e fechar regras por evento. Regra de firewall presa a um evento de
// fechamento vaza sempre que o evento se perde: chamado que nunca é encerrado
// formalmente, subrede temporária que expira sozinha, processo reiniciado no
// meio de uma sessão. Derivando sempre do banco, qualquer divergência se
// corrige na passada seguinte.
func (s *Server) StartSessionIsolationReconciler(ctx context.Context) {
	if s.Hub == nil {
		return
	}
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			if err := s.ExpireTemporarySubnetworks(ctx); err != nil {
				log.Printf("session-isolation: falha ao expirar subredes: %v", err)
			}
			if err := s.ReconcileSessionIsolation(ctx); err != nil {
				log.Printf("session-isolation: falha ao reconciliar: %v", err)
			}
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
}

// ExpireTemporarySubnetworks remove subredes de sessão cujo chamado já saiu de
// um estado ativo. É a rede de segurança para o fechamento que não passou pelo
// caminho normal.
//
// O critério é o estado do chamado, não o relógio: um atendimento pode levar
// dias, e cortar a sessão por prazo interromperia o trabalho no meio. Isso põe
// peso sobre o ciclo de vida do chamado — todo chamado/OS precisa chegar a um
// estado terminal, senão a subrede permanece. expires_at segue disponível para
// casos que queiram um limite explícito, mas não é preenchido por padrão.
func (s *Server) ExpireTemporarySubnetworks(ctx context.Context) error {
	_, err := s.Pool.Exec(ctx, `
		DELETE FROM subnetworks s
		WHERE s.ticket_id IS NOT NULL
		  AND (
		      (s.expires_at IS NOT NULL AND s.expires_at <= now())
		      OR NOT EXISTS (
		          SELECT 1 FROM support_tickets t
		          WHERE t.id = s.ticket_id
		            AND t.status NOT IN ('closed','cancelled','expired')
		      )
		  )`)
	return err
}

// ReconcileSessionIsolation aplica no hub exatamente os pares de endereços que
// compartilham alguma subrede não isolada.
//
// Participam os dispositivos (device_subnetworks) e os técnicos alocados à
// subrede (technician_assignments com escopo de subrede). O técnico entra pelo
// endereço da identidade de técnico — o adaptador tgdesk-tech0, que é o que o
// papel Técnico usa para operar — e não pelo endereço da máquina dele como
// dispositivo comum.
func (s *Server) ReconcileSessionIsolation(ctx context.Context) error {
	if s.Hub == nil {
		return nil
	}
	rows, err := s.Pool.Query(ctx, `
		WITH membros AS (
		    SELECT ds.subnetwork_id, d.wg_virtual_ip AS ip
		    FROM device_subnetworks ds
		    JOIN devices d ON d.id = ds.device_id
		    JOIN subnetworks s ON s.id = ds.subnetwork_id
		    WHERE NOT s.peer_isolation
		      AND s.status = 'ativa'
		      AND d.state = 'ativo'
		      AND coalesce(d.wg_virtual_ip,'') <> ''
		    UNION
		    -- O técnico entra pelo endereço da MÁQUINA dele, não por uma
		    -- identidade de rede separada: existe um adaptador só por
		    -- dispositivo, e o papel vem da credencial, não da rede. É
		    -- devices.control_technician_id que diz de quem é a máquina.
		    SELECT ta.subnetwork_id, d.wg_virtual_ip AS ip
		    FROM technician_assignments ta
		    JOIN technicians t ON t.id = ta.technician_id
		    JOIN devices d ON d.control_technician_id = t.id
		    JOIN subnetworks s ON s.id = ta.subnetwork_id
		    WHERE ta.assignment_scope = 'subnetwork'
		      AND NOT s.peer_isolation
		      AND s.status = 'ativa'
		      AND t.status = 'ativo'
		      AND d.state = 'ativo'
		      AND coalesce(d.wg_virtual_ip,'') <> ''
		)
		SELECT DISTINCT a.ip, b.ip
		FROM membros a JOIN membros b
		  ON a.subnetwork_id = b.subnetwork_id AND a.ip < b.ip`)
	if err != nil {
		return err
	}
	defer rows.Close()
	pairs := [][2]string{}
	for rows.Next() {
		var a, b string
		if rows.Scan(&a, &b) == nil {
			pairs = append(pairs, [2]string{a, b})
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	return s.Hub.ApplySessionPairs(pairs)
}
