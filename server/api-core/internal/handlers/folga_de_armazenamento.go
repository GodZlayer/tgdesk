package handlers

import (
	"context"
	"encoding/json"
	"fmt"
)

// Folga de armazenamento: onde ainda cabe, nesta máquina.
//
// "Disco cheio" nomeia três situações com resoluções que vão de GRÁTIS a
// comprar peça, e olhar um volume isolado não separa nenhuma delas:
//
//	1. partição cheia com espaço NÃO ALOCADO no disco → redimensionar
//	2. partição cheia, disco cheio, OUTRO disco com folga → mover arquivos
//	3. nenhuma folga em lugar nenhum → adicionar armazenamento
//
// As duas primeiras não custam nada, e eram invisíveis: a análise perguntava
// "este volume está cheio?" quando a pergunta útil é "existe folga em algum
// lugar desta máquina?".
//
// Medido no parque: uma máquina com C: a 98,2% e mais de 400 GB livres em
// outros três discos. A recomendação correta ali é mover arquivo, e a que o
// sistema daria era comprar armazenamento.

// FolgaDeArmazenamento é o retrato do espaço de uma máquina inteira.
type FolgaDeArmazenamento struct {
	Discos           int              `json:"discos"`
	VolumesSaturados []VolumeSaturado `json:"volumes_saturados"`
	NaoAlocadoGB     float64          `json:"nao_alocado_gb"`
	FolgaEmOutrosGB  float64          `json:"folga_em_outros_gb"`
	Resolucao        string           `json:"resolucao"`
	Explicacao       string           `json:"explicacao"`
}

// VolumeSaturado é um volume sem espaço útil, com o disco a que pertence.
type VolumeSaturado struct {
	Disco      string  `json:"disco"`
	Rotulo     string  `json:"rotulo"`
	TotalGB    float64 `json:"total_gb"`
	OcupadoPct float64 `json:"ocupado_pct"`
	Sistema    bool    `json:"sistema"`
}

// Limiar de saturação de volume.
//
// Não é limite de desempenho — para isso quem responde é o comportamento
// medido do disco sob carga, não a porcentagem. É só o ponto a partir do qual
// vale perguntar para onde mover.
const volumeSaturadoPct = 90.0

// AvaliarFolgaDeArmazenamento examina TODOS os discos de uma vez.
func (s *Server) AvaliarFolgaDeArmazenamento(ctx context.Context, deviceID string) (FolgaDeArmazenamento, error) {
	var f FolgaDeArmazenamento
	var bruto []byte
	err := s.Pool.QueryRow(ctx, `
		SELECT hardware->'storage'
		  FROM telemetry_snapshots
		 WHERE device_id = $1
		 ORDER BY coletado_em DESC
		 LIMIT 1`, deviceID).Scan(&bruto)
	if err != nil {
		return f, err
	}

	var discos []struct {
		Model      string  `json:"model"`
		TotalBytes float64 `json:"total_bytes"`
		Volumes    []struct {
			Label          string  `json:"label"`
			TotalBytes     float64 `json:"total_bytes"`
			AvailableBytes float64 `json:"available_bytes"`
			UsedPct        float64 `json:"used_pct"`
		} `json:"volumes"`
	}
	if err := json.Unmarshal(bruto, &discos); err != nil {
		return f, fmt.Errorf("inventário de armazenamento inválido: %w", err)
	}

	const gb = 1 << 30
	f.Discos = len(discos)
	var livreEmVolumesFolgados float64

	for _, d := range discos {
		var particionado float64
		for _, v := range d.Volumes {
			particionado += v.TotalBytes

			// Volume sem letra é partição de sistema (EFI, recuperação):
			// pequena por projeto e sempre cheia. Tratá-la como saturada
			// encheria o diagnóstico de alarme falso em toda máquina.
			if v.Label == "" {
				continue
			}
			if v.UsedPct >= volumeSaturadoPct {
				f.VolumesSaturados = append(f.VolumesSaturados, VolumeSaturado{
					Disco:      d.Model,
					Rotulo:     v.Label,
					TotalGB:    arredondarPct(v.TotalBytes / gb),
					OcupadoPct: arredondarPct(v.UsedPct),
					Sistema:    v.Label == "C:",
				})
			} else {
				livreEmVolumesFolgados += v.AvailableBytes
			}
		}
		// Espaço que existe no disco e não pertence a partição nenhuma.
		if sobra := d.TotalBytes - particionado; sobra > gb {
			f.NaoAlocadoGB += sobra / gb
		}
	}

	f.NaoAlocadoGB = arredondarPct(f.NaoAlocadoGB)
	f.FolgaEmOutrosGB = arredondarPct(livreEmVolumesFolgados / gb)
	f.Resolucao, f.Explicacao = concluirSobreFolga(f)
	return f, nil
}

// concluirSobreFolga escolhe a resolução MAIS BARATA que resolve.
//
// A ordem é deliberada: redimensionar não move dado nem custa dinheiro; mover
// arquivo custa tempo; comprar custa dinheiro. Recomendar compra tendo
// alternativa gratuita é o pior erro possível deste módulo, porque ele é
// invisível — o cliente compra, funciona, e ninguém descobre que não precisava.
func concluirSobreFolga(f FolgaDeArmazenamento) (string, string) {
	if len(f.VolumesSaturados) == 0 {
		return "nenhuma", "nenhum volume de uso está saturado"
	}

	nomes := ""
	for i, v := range f.VolumesSaturados {
		if i > 0 {
			nomes += ", "
		}
		nomes += fmt.Sprintf("%s (%.0f%%)", v.Rotulo, v.OcupadoPct)
	}

	switch {
	case f.NaoAlocadoGB >= 10:
		return "redimensionar", fmt.Sprintf(
			"%s sem espaço, mas há %.0f GB não alocados no próprio disco — "+
				"redimensionar resolve sem mover arquivo nem comprar nada",
			nomes, f.NaoAlocadoGB)
	case f.FolgaEmOutrosGB >= 20:
		return "mover arquivos", fmt.Sprintf(
			"%s sem espaço, e há %.0f GB livres em outros volumes desta mesma "+
				"máquina — mover arquivos de uso ocasional resolve sem comprar nada",
			nomes, f.FolgaEmOutrosGB)
	default:
		return "adicionar armazenamento", fmt.Sprintf(
			"%s sem espaço, e não há folga em nenhum outro volume nem espaço "+
				"não alocado — aqui é preciso mais armazenamento", nomes)
	}
}
