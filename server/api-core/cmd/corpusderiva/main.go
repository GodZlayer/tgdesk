// Comando de derivação do corpus (§13.6, trilhas A3 e A4).
//
// Lê os casos já ingeridos e produz: a demanda de sinais (o que os casos reais
// exigiram para serem resolvidos), a cobertura por classe de problema, e os
// priors de frequência. É a passagem que INVERTE a ordem causal do projeto —
// o corpus define o catálogo de testes e a telemetria, não o contrário.
//
// Nada do que sai daqui vale sozinho: tudo entra como rascunho, com contagem, e
// só passa a valer com `revisado_por` preenchido por gente.
//
// Uso:
//
//	corpusderiva -db postgres://... -min-casos 5
//	corpusderiva -db postgres://... -seco     (só relatório, não grava)
package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"os"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/corpus"
)

func main() {
	var (
		dbURL    = flag.String("db", os.Getenv("DATABASE_URL"), "URL do Postgres")
		minCasos = flag.Int("min-casos", 5, "piso de casos para um sinal sobreviver à poda")
		versao   = flag.String("versao-catalogo", "v1", "versão do catálogo medida no coverage_report")
		seco     = flag.Bool("seco", false, "só relatório, não grava")
	)
	flag.Parse()

	if *dbURL == "" {
		log.Fatal("faltou -db (ou DATABASE_URL)")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, *dbURL)
	if err != nil {
		log.Fatalf("conectando: %v", err)
	}
	defer pool.Close()

	casos, err := carregarCasos(ctx, pool)
	if err != nil {
		log.Fatalf("carregando casos: %v", err)
	}
	log.Printf("casos resolvidos com mensagem causal: %d", len(casos))
	if len(casos) == 0 {
		log.Fatal("nenhum caso resolvido: rode o corpusingest antes")
	}

	demanda := corpus.AgregarDemanda(casos)
	ficam, saem := corpus.Podar(demanda, *minCasos)

	log.Printf("sinais exigidos pelos casos: %d (ficam %d, podados %d)",
		len(demanda), len(ficam), len(saem))
	log.Print("--- sinais por poder de separação (o que decide, primeiro):")
	for n, d := range ficam {
		if n >= 25 {
			break
		}
		log.Printf("  %-22s casos=%-5d separação=%.2f  classes=%s",
			d.Sinal, d.CasosQueExigiram, d.GanhoDeInformacao,
			strings.Join(d.ClassesQueConsomem, ","))
	}

	// Cobertura contra o que o agente mede HOJE. É o número que substitui
	// achismo sobre o catálogo estar completo.
	disponiveis := sinaisQueOAgenteMedeHoje()
	cobertura := corpus.MedirCobertura(casos, disponiveis)
	log.Print("--- cobertura por classe (pior primeiro; agregado esconderia classe em zero):")
	for _, c := range cobertura {
		// Os dois buracos aparecem separados de propósito: "não medimos" é
		// backlog de agente; "não entendemos o texto" é vocabulário pobre do
		// extrator. Somados, mandariam a equipe construir sensor para um
		// problema que era de leitura.
		log.Printf("  %-12s crua %5.1f%%  instrumentada %5.1f%%  (%d de %d com medição citada; %d sem)  lacunas: %s",
			c.Classe, c.Cobertura*100, c.CoberturaInstrumentada*100,
			c.CasosDiscriminaveis, c.CasosTotal-c.CasosSemSinal, c.CasosSemSinal,
			resumo(c.Lacunas))
	}

	if *seco {
		log.Print("modo seco: nada foi gravado")
		return
	}
	if err := gravar(ctx, pool, demanda, cobertura, *versao, disponiveis); err != nil {
		log.Fatalf("gravando: %v", err)
	}
	log.Print("gravado em corpus.corpus_signal_demand e corpus.coverage_report")
	log.Print("ATENÇÃO: tudo entra como rascunho. Nada vale sem revisado_por.")
}

// carregarCasos monta o CasoDerivado a partir da MENSAGEM CAUSAL de cada caso
// resolvido — não da thread inteira. O que o autor tentou antes e não resolveu
// não é evidência da causa; é ruído com aparência de evidência.
func carregarCasos(ctx context.Context, pool *pgxpool.Pool) ([]corpus.CasoDerivado, error) {
	rows, err := pool.Query(ctx, `
		SELECT c.thread_id, coalesce(c.classe_problema,'indefinido'), p.corpo_txt
		FROM corpus.corpus_case c
		JOIN corpus.corpus_post p
		  ON p.thread_id = c.thread_id AND p.seq = c.seq_da_causa
		WHERE c.desfecho = 'resolvido'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var casos []corpus.CasoDerivado
	for rows.Next() {
		var id, classe, corpo string
		if err := rows.Scan(&id, &classe, &corpo); err != nil {
			return nil, err
		}
		casos = append(casos, corpus.CasoDerivado{
			ThreadID: id,
			Classe:   classe,
			Sinais:   corpus.ExtrairSinais(corpo),
			Testes:   corpus.ExtrairTestes(corpo),
		})
	}
	return casos, rows.Err()
}

// sinaisQueOAgenteMedeHoje é o mapeamento honesto do que já existe em
// `client-agent/cmd/agent/diagnostics.go` (§2 da arquitetura). Tudo o que não
// está aqui é backlog ou lacuna — e é exatamente essa diferença que a cobertura
// mede.
//
// Fica no código, e não em tabela, de propósito: é uma afirmação sobre o AGENTE,
// e tem que ser atualizada junto com ele. Em tabela, envelheceria em silêncio.
func sinaisQueOAgenteMedeHoje() map[string]bool {
	return map[string]bool{
		"smart_reallocated": true, // storageSurfaceRead + SMART
		"smart_pending":     true,
		"smart_geral":       true,
		"latencia_disco":    true, // diskPerformance / diskRandomPerformance
		"erro_memoria":      true, // memoryIntegrity / memoryExtended
		"uso_memoria":       true,
		"uso_cpu":           true, // cpuStress
		"temperatura":       true, // temperature_sensors
		"processo_pesado":   true, // process_pressure
		"erro_sistema_log":  true, // critical_events
		"driver_falho":      true, // driver_errors
		"servico_caiu":      true, // service_failures
		// Não medidos hoje — ficam de fora de propósito:
		//   erro_io_log, desligamento_subito, bugcheck (precisa ler dump),
		//   tensao (exige hardware externo → lacuna inviável),
		//   ventoinha, bateria, corrupcao_arquivo, boot_falho
	}
}

func gravar(
	ctx context.Context, pool *pgxpool.Pool,
	demanda []corpus.DemandaDeSinal, cobertura []corpus.Cobertura,
	versao string, disponiveis map[string]bool,
) error {
	for _, d := range demanda {
		classes, _ := json.Marshal(d.ClassesQueConsomem)
		// O veredito de viabilidade (passagem 3) é SUGERIDO aqui e confirmado
		// por gente: o que o agente já mede vira 'existe'; o resto entra como
		// 'construir' para triagem humana, nunca como 'inviavel' — declarar
		// algo inviável é decisão de engenharia, não de contagem.
		veredito := corpus.VereditoConstruir
		if disponiveis[d.Sinal] {
			veredito = corpus.VereditoExiste
		}
		if _, err := pool.Exec(ctx, `
			INSERT INTO corpus.corpus_signal_demand
				(sinal, casos_que_exigiram, causas_que_consomem, ganho_informacao, veredito)
			VALUES ($1,$2,$3,$4,$5)
			ON CONFLICT (sinal) DO UPDATE SET
				casos_que_exigiram=EXCLUDED.casos_que_exigiram,
				causas_que_consomem=EXCLUDED.causas_que_consomem,
				ganho_informacao=EXCLUDED.ganho_informacao,
				-- veredito revisado por gente NÃO é sobrescrito por recontagem.
				veredito=CASE WHEN corpus_signal_demand.revisado_por IS NULL
				              THEN EXCLUDED.veredito
				              ELSE corpus_signal_demand.veredito END`,
			d.Sinal, d.CasosQueExigiram, string(classes), d.GanhoDeInformacao, veredito,
		); err != nil {
			return err
		}
	}

	for _, c := range cobertura {
		lacunas, _ := json.Marshal(c.Lacunas)
		if _, err := pool.Exec(ctx, `
			INSERT INTO corpus.coverage_report
				(classe, versao_catalogo, casos_total, casos_discriminaveis, cobertura, lacunas)
			VALUES ($1,$2,$3,$4,$5,$6)
			ON CONFLICT (classe, versao_catalogo) DO UPDATE SET
				casos_total=EXCLUDED.casos_total,
				casos_discriminaveis=EXCLUDED.casos_discriminaveis,
				cobertura=EXCLUDED.cobertura,
				lacunas=EXCLUDED.lacunas,
				medido_em=now()`,
			c.Classe, versao, c.CasosTotal, c.CasosDiscriminaveis, c.Cobertura, string(lacunas),
		); err != nil {
			return err
		}
	}
	return nil
}

func resumo(lacunas []string) string {
	if len(lacunas) == 0 {
		return "nenhuma"
	}
	if len(lacunas) > 4 {
		return strings.Join(lacunas[:4], ",") + "…"
	}
	return strings.Join(lacunas, ",")
}
