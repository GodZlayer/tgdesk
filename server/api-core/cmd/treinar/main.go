// Treina os cabeçotes da rede a partir de `training_example` e grava os pesos
// em `model_version` (§14, §19.3).
//
// Roda de dentro do container do api-core — não existe serviço separado para
// treinar, pela mesma regra que trouxe a rede para cá: um container por
// projeto. O treino de um conjunto desta ordem leva segundos.
//
// Todo modelo sai daqui em SOMBRA. Promoção é decisão do gate de calibração
// sobre caso interno, nunca do treinador sobre si mesmo.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/diagnostico"
)

func main() {
	dsn := flag.String("db", os.Getenv("DATABASE_URL"), "banco operacional")
	gravar := flag.Bool("gravar", true, "grava os pesos em model_version")
	flag.Parse()

	if *dsn == "" {
		log.Fatal("faltou -db (ou DATABASE_URL)")
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, *dsn)
	if err != nil {
		log.Fatalf("banco: %v", err)
	}
	defer pool.Close()

	exemplos, err := diagnostico.CarregarExemplos(ctx, pool)
	if err != nil {
		log.Fatalf("exemplos: %v", err)
	}
	fmt.Printf("exemplos carregados: %d\n\n", len(exemplos))

	res := diagnostico.Treinar(exemplos)

	for _, t := range res.Treinados {
		fmt.Printf("== %s\n", t.Status)
		fmt.Printf("   causas      : %v\n", t.Causas)
		fmt.Printf("   n           : %d treino / %d validação (%d simulados)\n",
			t.NTreino, t.NValidacao, t.NSimulado)
		fmt.Printf("   perda       : %.4f -> %.4f\n", t.PerdaInicial, t.PerdaFinal)
		fmt.Printf("   temperatura : %.2f\n", t.Temperatura)
		fmt.Printf("   acurácia    : %.3f\n", t.Metricas.Acuracia)
		fmt.Printf("   log-loss    : %.3f  (regra: %.3f) -> melhor que a regra: %v\n",
			t.Metricas.LogLoss, t.LogLossRegra, t.MelhorQueARegra)
		fmt.Printf("   ECE         : %.4f  (gate de promoção: <= 0,05)\n", t.Metricas.ECE)
		for _, f := range t.Metricas.PorFaixa {
			fmt.Printf("      faixa %.0f-%.0f%%: n=%d, dizemos %.0f%%, acertamos %.0f%% (desvio %.1f pp)\n",
				f.De*100, f.Ate*100, f.N, f.ConfiancaMedia*100, f.AcertoReal*100, f.DesvioPP)
		}
		fmt.Printf("   hash        : %s\n\n", t.HashPesos)
	}

	for _, r := range res.Recusados {
		fmt.Printf("-- recusado %-24s n=%-3d %s\n", r.Status, r.N, r.Motivo)
	}

	if !*gravar {
		fmt.Println("\n-- nada gravado (-gravar=false)")
		return
	}
	if err := diagnostico.Gravar(ctx, pool, res); err != nil {
		log.Fatalf("gravação: %v", err)
	}
	fmt.Printf("\n-- gravados %d cabeçotes em model_version, todos em SOMBRA\n", len(res.Treinados))

	if b, err := json.Marshal(res); err == nil {
		_ = os.WriteFile("ultimo_treino.json", b, 0o644)
	}
}
