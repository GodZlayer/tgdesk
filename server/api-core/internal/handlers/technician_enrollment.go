package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	tgauth "tgdesk/api-core/internal/auth"
	"tgdesk/api-core/internal/middleware"
)

const (
	controlKeyFormat       = "tgdesk-control-key-v1"
	legacyTechnicianFormat = "tgdesk-tech-key-v1"
)

type createEnrollmentKeyRequest struct {
	ExpiresInHours int `json:"expires_in_hours"`
}

type enrollmentKeyFile struct {
	Format   string `json:"format"`
	KeyID    string `json:"key_id"`
	Secret   string `json:"secret"`
	ServerID string `json:"server_id"`
}

type redeemEnrollmentRequest struct {
	Key       enrollmentKeyFile `json:"key"`
	MachineID string            `json:"machine_id"`
}

type refreshMachineRequest struct {
	CredentialID string `json:"credential_id"`
	Secret       string `json:"secret"`
	MachineID    string `json:"machine_id"`
}

type machineAuthResponse struct {
	Token        string `json:"token"`
	Role         string `json:"role"`
	Username     string `json:"username"`
	CredentialID string `json:"credential_id,omitempty"`
	Secret       string `json:"secret,omitempty"`
	MachineID    string `json:"machine_id,omitempty"`
}

func randomURLSecret() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func secretDigest(secret string) []byte {
	sum := sha256.Sum256([]byte(secret))
	return sum[:]
}

func enrollmentServerID(jwtSecret string) string {
	return hex.EncodeToString(secretDigest(jwtSecret))[:16]
}

// CreateTechnicianEnrollmentKey returns the complete .tgdesk-key payload once.
// Only its digest remains in PostgreSQL.
func (s *Server) CreateTechnicianEnrollmentKey(w http.ResponseWriter, r *http.Request, technicianID string) {
	var req createEnrollmentKeyRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.ExpiresInHours <= 0 {
		req.ExpiresInHours = 72
	}
	if req.ExpiresInHours > 24*30 {
		writeErr(w, http.StatusBadRequest, "validade máxima é 30 dias")
		return
	}

	secret, err := randomURLSecret()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao gerar chave")
		return
	}
	var keyID string
	claims := middleware.ClaimsFrom(r.Context())
	err = s.Pool.QueryRow(r.Context(), `
		INSERT INTO technician_enrollment_keys
		    (technician_id, secret_hash, expires_at, created_by)
		SELECT id, $2, now() + ($3 * interval '1 hour'), $4
		FROM technicians WHERE id=$1 AND status='ativo'
		RETURNING id`,
		technicianID, secretDigest(secret), req.ExpiresInHours, claims.TechnicianID,
	).Scan(&keyID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "técnico ativo não encontrado")
		return
	}

	writeJSON(w, http.StatusCreated, enrollmentKeyFile{
		Format: controlKeyFormat, KeyID: keyID, Secret: secret,
		ServerID: enrollmentServerID(s.Cfg.JWTSecret),
	})
}

// ValidateTechnicianEnrollment confere a chave sem consumi-la, para que o
// instalador possa recusar um arquivo inválido na própria tela de seleção.
//
// A chave é de uso único: consumi-la antes da remoção da instalação anterior
// significaria queimá-la se a remoção falhasse, deixando o técnico sem chave e
// sem instalação. Por isso a validação vem aqui, e o consumo continua em
// RedeemTechnicianEnrollment, já com a máquina limpa.
func (s *Server) ValidateTechnicianEnrollment(w http.ResponseWriter, r *http.Request) {
	var req redeemEnrollmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil ||
		(req.Key.Format != controlKeyFormat && req.Key.Format != legacyTechnicianFormat) ||
		req.Key.KeyID == "" ||
		req.Key.Secret == "" ||
		req.Key.ServerID != enrollmentServerID(s.Cfg.JWTSecret) {
		writeErr(w, http.StatusBadRequest, "arquivo-chave inválido")
		return
	}
	var username, role, status string
	var storedHash []byte
	var expiresAt, consumedAt *time.Time
	err := s.Pool.QueryRow(r.Context(), `
		SELECT t.username, t.role, t.status, k.secret_hash,
		       k.expires_at, k.consumed_at
		FROM technician_enrollment_keys k
		JOIN technicians t ON t.id=k.technician_id
		WHERE k.id=$1`, req.Key.KeyID,
	).Scan(&username, &role, &status, &storedHash, &expiresAt, &consumedAt)
	if err != nil || status != "ativo" ||
		!equalDigest(storedHash, secretDigest(req.Key.Secret)) {
		writeErr(w, http.StatusUnauthorized, "chave inválida")
		return
	}
	if consumedAt != nil {
		writeErr(w, http.StatusConflict, "chave já utilizada")
		return
	}
	if expiresAt != nil && time.Now().After(*expiresAt) {
		writeErr(w, http.StatusGone, "chave expirada")
		return
	}
	// A marca vai junto: o servidor já sabe de quem é a chave, então o
	// instalador não precisa de uma segunda volta nem de descobrir o id do
	// técnico. O computador dele nasce com a marca dele, como o do cliente.
	response := map[string]any{"role": role, "username": username}
	var technicianID string
	if s.Pool.QueryRow(r.Context(),
		`SELECT technician_id FROM technician_enrollment_keys WHERE id=$1`,
		req.Key.KeyID).Scan(&technicianID) == nil {
		if record, brandErr := s.technicianBrand(r.Context(), technicianID); brandErr == nil {
			response["branding"] = brandJSON(record, true)
		}
	}
	writeJSON(w, http.StatusOK, response)
}

// RedeemTechnicianEnrollment atomically consumes a one-time key and binds the
// resulting credential to the supplied Windows machine identity.
func (s *Server) RedeemTechnicianEnrollment(w http.ResponseWriter, r *http.Request) {
	var req redeemEnrollmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil ||
		(req.Key.Format != controlKeyFormat && req.Key.Format != legacyTechnicianFormat) ||
		req.Key.KeyID == "" ||
		req.Key.Secret == "" ||
		req.Key.ServerID != enrollmentServerID(s.Cfg.JWTSecret) ||
		strings.TrimSpace(req.MachineID) == "" {
		writeErr(w, http.StatusBadRequest, "arquivo-chave inválido")
		return
	}

	tx, err := s.Pool.BeginTx(r.Context(), pgx.TxOptions{})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao iniciar ativação")
		return
	}
	defer tx.Rollback(r.Context())

	var technicianID, username, role, status string
	var storedHash []byte
	var expiresAt *time.Time
	var consumedAt *time.Time
	err = tx.QueryRow(r.Context(), `
		SELECT t.id, t.username, t.role, t.status, k.secret_hash,
		       k.expires_at, k.consumed_at
		FROM technician_enrollment_keys k
		JOIN technicians t ON t.id=k.technician_id
		WHERE k.id=$1
		FOR UPDATE`, req.Key.KeyID,
	).Scan(&technicianID, &username, &role, &status, &storedHash, &expiresAt, &consumedAt)
	if err != nil || status != "ativo" ||
		!equalDigest(storedHash, secretDigest(req.Key.Secret)) {
		writeErr(w, http.StatusUnauthorized, "chave inválida")
		return
	}
	if consumedAt != nil {
		writeErr(w, http.StatusConflict, "chave já utilizada")
		return
	}
	if expiresAt != nil && time.Now().After(*expiresAt) {
		writeErr(w, http.StatusGone, "chave expirada")
		return
	}

	machineSecret, err := randomURLSecret()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao emitir credencial")
		return
	}
	var credentialID string
	machineID := strings.TrimSpace(req.MachineID)
	err = tx.QueryRow(r.Context(), `
		INSERT INTO technician_machine_credentials
		    (technician_id, machine_id, machine_fingerprint, credential_hash, control_role)
		VALUES ($1, $2, $2, $3, $4)
		ON CONFLICT (technician_id, machine_id) DO UPDATE
		    SET credential_hash=EXCLUDED.credential_hash, status='ativo',
		        machine_fingerprint=EXCLUDED.machine_fingerprint,
		        control_role=EXCLUDED.control_role, last_used_at=now()
		RETURNING id`,
		technicianID, machineID, secretDigest(machineSecret), role,
	).Scan(&credentialID)
	if err != nil {
		if role == "super_admin" {
			writeErr(w, http.StatusConflict, "já existe um computador Admin ativo")
			return
		}
		writeErr(w, http.StatusInternalServerError, "falha ao vincular computador")
		return
	}
	if _, err = tx.Exec(r.Context(), `
		UPDATE technician_enrollment_keys
		SET consumed_at=now(), consumed_machine_id=$2 WHERE id=$1`,
		req.Key.KeyID, machineID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao consumir chave")
		return
	}
	if err = tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusConflict, "chave utilizada simultaneamente")
		return
	}

	token, err := tgauth.IssueToken(s.Cfg.JWTSecret, technicianID, username, role)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao emitir sessão")
		return
	}
	writeJSON(w, http.StatusOK, machineAuthResponse{
		Token: token, Role: role, Username: username,
		CredentialID: credentialID, Secret: machineSecret, MachineID: machineID,
	})
}

func (s *Server) RefreshTechnicianMachine(w http.ResponseWriter, r *http.Request) {
	var req refreshMachineRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil ||
		req.CredentialID == "" || req.Secret == "" || strings.TrimSpace(req.MachineID) == "" {
		writeErr(w, http.StatusBadRequest, "credencial inválida")
		return
	}
	var technicianID, username, role, status, machineID string
	var storedHash []byte
	err := s.Pool.QueryRow(r.Context(), `
		SELECT t.id, t.username, t.role, t.status, c.machine_id, c.credential_hash
		FROM technician_machine_credentials c
		JOIN technicians t ON t.id=c.technician_id
		WHERE c.id=$1 AND c.status='ativo'`, req.CredentialID,
	).Scan(&technicianID, &username, &role, &status, &machineID, &storedHash)
	if err != nil || status != "ativo" || machineID != strings.TrimSpace(req.MachineID) ||
		!equalDigest(storedHash, secretDigest(req.Secret)) {
		writeErr(w, http.StatusUnauthorized, "credencial revogada ou inválida")
		return
	}
	_, _ = s.Pool.Exec(r.Context(),
		`UPDATE technician_machine_credentials SET last_used_at=now() WHERE id=$1`,
		req.CredentialID)
	token, err := tgauth.IssueToken(s.Cfg.JWTSecret, technicianID, username, role)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao emitir sessão")
		return
	}
	writeJSON(w, http.StatusOK, machineAuthResponse{
		Token: token, Role: role, Username: username,
	})
}

func equalDigest(left, right []byte) bool {
	if len(left) != len(right) {
		return false
	}
	var diff byte
	for i := range left {
		diff |= left[i] ^ right[i]
	}
	return diff == 0
}
