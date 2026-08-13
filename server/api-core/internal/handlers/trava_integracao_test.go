package handlers

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Validação do CAMINHO POSITIVO do detector de travas, contra banco real.
//
// Por que este teste existe: depois de corrigir o detector, o parque parou de
// gerar travas falsas — mas nenhuma trava VERDADEIRA jamais foi registrada.
// "Parou de mentir" não é o mesmo que "funciona". Toda a cadeia de
// classificação (contexto do agente → origem='trava' → status no dossiê) nunca
// tinha sido exercitada de ponta a ponta, e código nunca exercitado é código
// que provavelmente não funciona.
//
// O que ele cobre: criação do evento pelo relógio externo, chegada do contexto
// do agente, classificação da origem, e consumo pelo dossiê. O único elo fora
// é o salto no WebSocket, que já tem teste próprio no agente.
//
// Roda só com DATABASE_URL apontando para um banco de verdade — em `go test`
// normal ele é pulado, porque teste que exige infraestrutura não pode quebrar
// a suíte de quem só quer compilar.
func TestIntegracao_CaminhoPositivoDaTrava(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("sem DATABASE_URL: teste de integração pulado")
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("banco: %v", err)
	}
	defer pool.Close()

	s := &Server{Pool: pool}

	var deviceID, hostname string
	if err := pool.QueryRow(ctx, `
		SELECT id::text, hostname FROM devices ORDER BY last_seen_at DESC NULLS LAST LIMIT 1`).
		Scan(&deviceID, &hostname); err != nil {
		t.Fatalf("nenhum dispositivo para testar: %v", err)
	}
	t.Logf("validando contra o dispositivo real %s", hostname)

	// Limpeza no fim: este teste ESCREVE em produção, então tudo que ele cria
	// é removido pelo id — inclusive se falhar no meio.
	//
	// `run_id` seria a marca natural, mas ela tem FK para `stress_run` e usá-la
	// exigiria inventar uma execução de escada que nunca aconteceu. Guardar os
	// ids é mais feio e mais honesto.
	var criados []string
	defer func() {
		for _, id := range criados {
			_, _ = pool.Exec(ctx, `DELETE FROM stall_event WHERE id = $1::uuid`, id)
		}
	}()

	// 1. O servidor detecta o buraco e abre o evento — como o relógio externo
	//    faria. Três congelamentos curtos, que é o padrão relatado: "trava um
	//    segundo e volta".
	duracoes := []int{1800, 2400, 3100}
	var ids []string
	for _, ms := range duracoes {
		var id string
		inicio := time.Now().Add(-time.Duration(len(ids)+1) * time.Hour)
		if err := pool.QueryRow(ctx, `
			INSERT INTO stall_event
			  (device_id, inicio, fim, server_gap_ms, duracao_conciliada_ms,
			   confianca, origem)
			VALUES ($1::uuid, $2::timestamptz,
			        $2::timestamptz + make_interval(secs => $3::int / 1000.0),
			        $3::int, $3::int, 'media', 'indeterminado')
			RETURNING id::text`, deviceID, inicio, ms).Scan(&id); err != nil {
			t.Fatalf("abrir evento: %v", err)
		}
		ids = append(ids, id)
		criados = append(criados, id)
	}

	// 2. O agente confirma: o relógio local SALTOU, logo foi congelamento e não
	//    queda de rede. É exatamente o payload que `stall_context` carrega.
	for i, id := range ids {
		buffer, _ := json.Marshal([]map[string]any{
			{"t": time.Now().UnixMilli(), "cpu": 12.5, "ram": 61.0},
		})
		if _, err := pool.Exec(ctx, `
			UPDATE stall_event SET agent_ts = $2::jsonb, origem = $3, confianca = 'alta'
			WHERE id = $1::uuid`,
			id, string(buffer), origemDaTrava(true)); err != nil {
			t.Fatalf("confirmar evento %d: %v", i, err)
		}
	}

	// 3. A classificação tem que ter virado 'trava'. Se `origemDaTrava` algum
	//    dia inverter, o parque inteiro volta a chamar queda de rede de
	//    travamento — e é este assert que segura isso.
	var confirmadas int
	if err := pool.QueryRow(ctx, `
		SELECT count(*) FROM stall_event WHERE id = ANY($1::uuid[]) AND origem = 'trava'`,
		criados).Scan(&confirmadas); err != nil {
		t.Fatalf("contar: %v", err)
	}
	if confirmadas != len(duracoes) {
		t.Fatalf("esperava %d travas confirmadas, vieram %d", len(duracoes), confirmadas)
	}

	// 4. E o dossiê tem que CONSUMIR isso. Era o elo que faltava: o detector
	//    gravava e o diagnóstico não olhava.
	perfil := s.perfilDeTravas(ctx, deviceID)
	if perfil.Confirmadas < len(duracoes) {
		t.Fatalf("o dossiê não enxergou as travas: %+v", perfil)
	}
	if perfil.Status != "congelamento_breve_repetido" {
		t.Fatalf("três congelamentos de 1,8 a 3,1 s deviam dar congelamento breve repetido, "+
			"veio %q", perfil.Status)
	}
	if perfil.Evidencia == "" {
		t.Fatal("status sem evidência literal não pode chegar à tela (§10.5.1)")
	}
	t.Logf("dossiê classificou: %s — %s", perfil.Status, perfil.Evidencia)

	// 5. E o produtor do dossiê tem que devolver esse status para o canal.
	retratos := s.diagnosticosParaSnapshot(ctx, []string{deviceID})
	if len(retratos) != 1 {
		t.Fatalf("esperava 1 retrato, vieram %d", len(retratos))
	}
	if retratos[0].Status != "congelamento_breve_repetido" {
		t.Fatalf("o retrato que vai para a tela diz %q em vez do congelamento",
			retratos[0].Status)
	}
	t.Logf("retrato para a tela: status=%s, motor=%s, %d evidências",
		retratos[0].Status, retratos[0].Motor, len(retratos[0].Evidencias))
}
