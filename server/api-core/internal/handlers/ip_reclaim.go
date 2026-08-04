package handlers

import (
	"context"
	"log"
	"time"
)

// IPReclaimAfter é a inatividade a partir da qual o endereço virtual de um
// dispositivo é devolvido ao pool da rede.
const IPReclaimAfter = 30 * 24 * time.Hour

// StartIPReclaimer roda a coleta de endereços inativos uma vez ao subir e
// depois uma vez por dia.
//
// Sem isso a reciclagem de octetos não faz sentido: next_host_octet só cresce,
// então cada reinstalação queima um endereço para sempre e o espaço da rede se
// esgota bem antes dos ~253 dispositivos nominais.
func (s *Server) StartIPReclaimer(ctx context.Context) {
	go func() {
		ticker := time.NewTicker(24 * time.Hour)
		defer ticker.Stop()
		for {
			if released, err := s.ReclaimInactiveIPs(ctx); err != nil {
				log.Printf("ip-reclaimer: falha ao liberar endereços: %v", err)
			} else if released > 0 {
				log.Printf("ip-reclaimer: %d endereços virtuais devolvidos ao pool", released)
			}
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
}

// ReclaimInactiveIPs devolve ao pool o endereço de todo dispositivo sem
// contato há mais de IPReclaimAfter, removendo também o peer do hub — reciclar
// o endereço sem remover o peer deixaria dois peers com o mesmo allowed_ip.
//
// O dispositivo e todo o seu histórico de telemetria permanecem intactos: só o
// endereço e a chave WireGuard são liberados. Quando a máquina voltar, o
// agente chama /devices/wg-key na subida do túnel e recebe um endereço novo,
// sem intervenção de ninguém.
func (s *Server) ReclaimInactiveIPs(ctx context.Context) (int, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT id, network_id, wg_pubkey, wg_virtual_ip FROM devices
		WHERE coalesce(wg_virtual_ip,'') <> ''
		  AND network_id IS NOT NULL
		  AND coalesce(last_seen_at, updated_at, created_at) < now() - $1::interval`,
		IPReclaimAfter.String())
	if err != nil {
		return 0, err
	}
	type stale struct{ id, networkID, pubkey, ip string }
	pending := []stale{}
	for rows.Next() {
		var d stale
		var pubkey *string
		if rows.Scan(&d.id, &d.networkID, &pubkey, &d.ip) == nil {
			if pubkey != nil {
				d.pubkey = *pubkey
			}
			pending = append(pending, d)
		}
	}
	rows.Close()

	released := 0
	for _, d := range pending {
		// Remove o peer antes de devolver o endereço: enquanto o peer existir
		// no hub, o endereço ainda está em uso de fato.
		if s.Hub != nil && d.pubkey != "" {
			if err := s.Hub.RemovePeer(d.pubkey); err != nil {
				log.Printf("ip-reclaimer: peer %s não removido (%v), endereço mantido", d.id, err)
				continue
			}
		}
		if _, err := s.Pool.Exec(ctx,
			`SELECT release_virtual_ip($1,$2)`, d.networkID, d.ip); err != nil {
			log.Printf("ip-reclaimer: falha ao devolver %s: %v", d.ip, err)
			continue
		}
		if _, err := s.Pool.Exec(ctx, `
			UPDATE devices SET wg_virtual_ip=NULL, wg_pubkey=NULL, updated_at=now()
			WHERE id=$1`, d.id); err != nil {
			log.Printf("ip-reclaimer: falha ao limpar dispositivo %s: %v", d.id, err)
			continue
		}
		released++
	}
	return released, nil
}
