package handlers

import (
	"fmt"
	"net"
	"net/http"

	"tgdesk/api-core/internal/middleware"
)

// buildMagicPacket monta o pacote clássico de Wake-on-LAN: 6 bytes 0xFF
// seguidos do MAC alvo repetido 16 vezes.
func buildMagicPacket(mac net.HardwareAddr) []byte {
	packet := make([]byte, 0, 102)
	for i := 0; i < 6; i++ {
		packet = append(packet, 0xFF)
	}
	for i := 0; i < 16; i++ {
		packet = append(packet, mac...)
	}
	return packet
}

// sendMagicPacket faz o broadcast UDP na porta 9 (padrão WoL). MVP direto do
// servidor — sem o relé por "peer proxy" descrito na Seção 8.E, que exige um
// vizinho sempre ligado na mesma rede local do dispositivo alvo. Documentado
// como próximo passo em ARCHITECTURE_FLOW.md.
func sendMagicPacket(mac net.HardwareAddr) error {
	conn, err := net.Dial("udp", "255.255.255.255:9")
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Write(buildMagicPacket(mac))
	return err
}

// WakeDevice implementa o Módulo E (Wake-on-LAN) — RBAC igual aos outros
// endpoints de dispositivo: super_admin vê tudo, técnico só o que está em
// technician_assignments.
func (s *Server) WakeDevice(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())

	var macStr string
	var orgID, netID string
	err := s.Pool.QueryRow(r.Context(), `
		SELECT coalesce(d.mac,''), n.organization_id, n.id FROM devices d
		JOIN networks n ON d.network_id = n.id
		WHERE d.id=$1`, deviceID,
	).Scan(&macStr, &orgID, &netID)
	if err != nil {
		writeErrCode(w, http.StatusNotFound, "dispositivo_encontrado_vinculado", "dispositivo não encontrado ou não vinculado")
		return
	}
	// Check authorization using centralized authorizer
	ok, err := s.Authorizer.CanAccessDevice(r.Context(), claims, deviceID)
	if err != nil || !ok {
		writeErrCode(w, http.StatusForbidden, "permissao_dispositivo", "sem permissão para esse dispositivo")
		return
	}
	if macStr == "" {
		writeErrCode(w, http.StatusUnprocessableEntity, "dispositivo_mac_registrado", "dispositivo sem MAC registrado")
		return
	}
	mac, err := net.ParseMAC(macStr)
	if err != nil {
		writeErrCode(w, http.StatusUnprocessableEntity, "mac_invalido", fmt.Sprintf("MAC inválido: %s", macStr))
		return
	}

	if err := sendMagicPacket(mac); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_enviar_magic_packet", "falha ao enviar magic packet: "+err.Error())
		return
	}

	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO admin_actions (actor_id, tipo, alvo_id) VALUES ($1, 'wake', $2)`,
		claims.TechnicianID, deviceID)

	writeJSON(w, http.StatusOK, map[string]string{"status": "magic packet enviado"})
}
