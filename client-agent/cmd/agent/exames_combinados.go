//go:build windows

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/exec"
	"runtime"
	"sort"
	"time"
)

// Exames COMBINADOS: medir peças trabalhando juntas.
//
// Todo o instrumental existente mede uma peça de cada vez, isolada, e é por
// isso que ele erra num caso inteiro de máquina.
//
// A prova veio do parque. Numa máquina com 8 GB, os três exames de disco
// dizem que ele está ótimo — SMART saudável, 9.863 IOPS, varredura inteira
// entre 185 e 269 MB/s — enquanto o uso cotidiano registra p99 de 2.137 ms e
// travamentos de segundos. Nenhum teste isolado viu, porque o problema do
// disco daquela máquina não existe quando ele está sozinho: existe quando a
// memória acaba e ele vira memória.
//
// O eixo que faltava é este. Peça isolada responde "tem defeito?"; peças
// juntas respondem "esta máquina aguenta este uso?" — que é a pergunta que o
// cliente realmente faz.
//
// Todos os exames deste arquivo são de LEITURA. Nenhum escreve em disco,
// nenhum apaga nada, nenhum altera configuração.

// ---------------------------------------------------------------------------
// Banda de memória
// ---------------------------------------------------------------------------

// bandaDeMemoria mede quantos GB/s a memória entrega de fato.
//
// É o eixo de DESEMPENHO da RAM, que simplesmente não existia: havia teste de
// integridade (a memória erra?) e nenhum de entrega (a memória rende?).
//
// Ele importa por um motivo concreto medido no parque: uma das máquinas tem
// 32 GB DDR5 num único módulo. Módulo único significa canal único, e canal
// único é metade da banda — algo invisível para qualquer teste de integridade,
// porque a memória está perfeita, só que pela metade. Numa máquina cujo vídeo
// é integrado, essa metade é disputada também pelo gráfico.
//
// O método é uma cópia grande e repetida entre dois blocos, no estilo do
// STREAM: o gargalo de copiar 128 MB não é o processador, é o barramento.
func bandaDeMemoria(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	const (
		blocoBytes = 64 * 1024 * 1024
		repeticoes = 8
	)
	progress(10, "Reservando blocos para medir banda")
	origem := make([]byte, blocoBytes)
	destino := make([]byte, blocoBytes)
	for i := range origem {
		origem[i] = byte(i)
	}

	amostras := make([]float64, 0, repeticoes)
	for r := 0; r < repeticoes; r++ {
		if err := waitDiagnosticPause(ctx); err != nil {
			return map[string]any{}, err
		}
		if ctx.Err() != nil {
			return map[string]any{}, ctx.Err()
		}
		inicio := time.Now()
		copy(destino, origem)
		decorrido := time.Since(inicio)
		if decorrido > 0 {
			gbps := float64(blocoBytes) / decorrido.Seconds() / (1 << 30)
			amostras = append(amostras, gbps)
		}
		progress(10+r*10, fmt.Sprintf("Medindo banda (%d de %d)", r+1, repeticoes))
	}
	if len(amostras) == 0 {
		return map[string]any{}, fmt.Errorf("nenhuma medição de banda concluída")
	}

	sort.Float64s(amostras)
	// A MEDIANA, não a média. Uma repetição atrapalhada por outro processo
	// puxa a média para baixo e vira "memória lenta" numa máquina sadia — o
	// mesmo erro que já custou caro na varredura de disco.
	return map[string]any{
		"gb_por_segundo":        arredondar(mediana(amostras), 2),
		"melhor_gb_por_segundo": arredondar(amostras[len(amostras)-1], 2),
		"pior_gb_por_segundo":   arredondar(amostras[0], 2),
		"bloco_mb":              blocoBytes / (1024 * 1024),
		"repeticoes":            len(amostras),
	}, nil
}

// ---------------------------------------------------------------------------
// Núcleos do processador
// ---------------------------------------------------------------------------

// nucleosDoProcessador mede a entrega de CADA núcleo separadamente.
//
// É o eixo de PARTE RUIM do processador — o equivalente à varredura de
// superfície do disco. Um núcleo que rende menos que os irmãos aponta
// throttling térmico localizado ou defeito; a média entre todos apaga isso
// exatamente como apagava o engasgo do disco.
//
// Limitação declarada: sem fixar afinidade, o escalonador do sistema pode
// mover a rotina entre núcleos, então isto mede a DISPERSÃO da entrega
// paralela, não cada núcleo nominalmente. É suficiente para detectar "um
// caroço está muito pior que o resto", que é a pergunta.
func nucleosDoProcessador(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	nucleos := runtime.NumCPU()
	if nucleos < 1 {
		return map[string]any{}, fmt.Errorf("número de núcleos indisponível")
	}
	progress(15, fmt.Sprintf("Medindo entrega de %d núcleos", nucleos))

	const duracao = 900 * time.Millisecond
	resultados := make([]float64, nucleos)
	pronto := make(chan int, nucleos)

	for n := 0; n < nucleos; n++ {
		go func(indice int) {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()
			limite := time.Now().Add(duracao)
			var voltas float64
			var acumulado uint64 = 1
			for time.Now().Before(limite) {
				// Trabalho aritmético puro, sem tocar em memória grande: o que
				// se quer medir aqui é o núcleo, não o barramento.
				for i := 0; i < 20000; i++ {
					acumulado = acumulado*6364136223846793005 + 1442695040888963407
				}
				voltas++
			}
			if acumulado == 0 {
				voltas = 0 // impede o compilador de descartar o laço
			}
			resultados[indice] = voltas
			pronto <- indice
		}(n)
	}
	for n := 0; n < nucleos; n++ {
		select {
		case <-pronto:
		case <-ctx.Done():
			return map[string]any{}, ctx.Err()
		}
	}

	ordenado := append([]float64(nil), resultados...)
	sort.Float64s(ordenado)
	med := mediana(ordenado)
	pior := ordenado[0]
	desvio := 0.0
	if med > 0 {
		desvio = (med - pior) / med * 100
	}

	porNucleo := make([]map[string]any, 0, nucleos)
	for i, v := range resultados {
		relativo := 0.0
		if med > 0 {
			relativo = v / med * 100
		}
		porNucleo = append(porNucleo, map[string]any{
			"nucleo": i, "voltas": v, "relativo_pct": arredondar(relativo, 1),
		})
	}

	return map[string]any{
		"nucleos":                nucleos,
		"por_nucleo":             porNucleo,
		"mediana_voltas":         med,
		"pior_abaixo_da_med_pct": arredondar(desvio, 1),
		"limitacao":              "sem fixação de afinidade: mede dispersão da entrega paralela, não cada núcleo nominalmente",
	}, nil
}

// ---------------------------------------------------------------------------
// Pressão de paginação — memória + disco
// ---------------------------------------------------------------------------

// pressaoDePaginacao mede o que acontece com o DISCO quando a MEMÓRIA aperta.
//
// Este é o exame que responde o caso real que motivou todo este arquivo. A
// hipótese: numa máquina com pouca RAM, o Windows pagina; o arquivo de
// paginação mora no disco; e um disco lento transforma falta de memória em
// congelamento de segundos. Isolado, nem a memória nem o disco acusam nada.
//
// O método: ocupar memória em degraus e, a cada degrau, medir a latência de
// leitura do disco físico. Se a hipótese vale, existe um JOELHO — um ponto a
// partir do qual a latência dispara. A posição desse joelho é a resposta:
// quanta folga de memória a máquina precisa para não congelar.
//
// SEGURANÇA. Este exame ocupa memória de propósito, então ele pode causar
// justamente o travamento que investiga. As travas são conservadoras e
// obrigatórias:
//
//   - nunca ocupa mais que 40% do que está livre no momento;
//   - teto absoluto de 1,5 GB, independente do tamanho da máquina;
//   - aborta imediatamente se a memória disponível cair abaixo de 12% do total;
//   - devolve tudo ao fim, inclusive quando aborta ou o contexto é cancelado.
//
// Nada é escrito em disco: as leituras são no dispositivo físico, em modo
// somente leitura.
func pressaoDePaginacao(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	if runtime.GOOS != "windows" {
		return map[string]any{}, fmt.Errorf("pressão de paginação disponível somente no Windows")
	}

	const (
		degrauMB      = 128
		tetoMB        = 1536
		fracaoDoLivre = 0.40
		pisoLivrePct  = 12.0
	)

	inicial := ColetarBarato()
	totalMB := float64(0)
	if inicial.MemPct > 0 {
		totalMB = float64(inicial.MemDispMB) / (1 - inicial.MemPct/100)
	}
	if totalMB <= 0 {
		return map[string]any{}, fmt.Errorf("memória total indisponível")
	}

	limiteMB := int(float64(inicial.MemDispMB) * fracaoDoLivre)
	if limiteMB > tetoMB {
		limiteMB = tetoMB
	}
	if limiteMB < degrauMB {
		return map[string]any{
			"pulado":   true,
			"motivo":   "memória livre insuficiente para medir com segurança",
			"livre_mb": inicial.MemDispMB,
		}, nil
	}

	arquivo, tamanhoDisco, err := abrirDiscoPrincipal(ctx)
	if err != nil {
		return map[string]any{}, err
	}
	defer arquivo.Close()

	// Mantida viva até o fim para que a memória permaneça REALMENTE ocupada;
	// liberada pelo coletor assim que a função retorna.
	var ocupada [][]byte
	defer func() { ocupada = nil; runtime.GC() }()

	buffer := make([]byte, 1024*1024)
	degraus := make([]map[string]any, 0, limiteMB/degrauMB+1)
	abortou := ""

	medir := func(alocadoMB int) {
		lat := latenciaDeLeitura(arquivo, tamanhoDisco, buffer, 12)
		amostra := ColetarBarato()
		degraus = append(degraus, map[string]any{
			"ocupado_mb":          alocadoMB,
			"livre_mb":            amostra.MemDispMB,
			"commit_pct":          arredondar(amostra.CommitPct, 1),
			"latencia_mediana_ms": arredondar(lat.mediana, 3),
			"latencia_p95_ms":     arredondar(lat.p95, 3),
			"latencia_pior_ms":    arredondar(lat.pior, 3),
		})
	}

	medir(0)
	for alocado := degrauMB; alocado <= limiteMB; alocado += degrauMB {
		if err := waitDiagnosticPause(ctx); err != nil {
			return resultadoDaPressao(degraus, "pausa/cancelamento", totalMB), err
		}
		if ctx.Err() != nil {
			return resultadoDaPressao(degraus, "cancelado", totalMB), ctx.Err()
		}
		amostra := ColetarBarato()
		if float64(amostra.MemDispMB)/totalMB*100 < pisoLivrePct {
			abortou = "piso de memória livre atingido — interrompido para não travar a máquina"
			break
		}
		bloco := make([]byte, degrauMB*1024*1024)
		// Tocar cada página é o que de fato compromete memória física; sem
		// isso o sistema apenas reserva endereço e nada acontece.
		for i := 0; i < len(bloco); i += 4096 {
			bloco[i] = byte(i)
		}
		ocupada = append(ocupada, bloco)
		progress(10+alocado*80/limiteMB, fmt.Sprintf("Ocupando %d MB e medindo o disco", alocado))
		medir(alocado)
	}

	return resultadoDaPressao(degraus, abortou, totalMB), nil
}

func resultadoDaPressao(degraus []map[string]any, aviso string, totalMB float64) map[string]any {
	saida := map[string]any{
		"degraus":  degraus,
		"total_mb": int(totalMB),
	}
	if aviso != "" {
		saida["interrompido"] = aviso
	}
	// O JOELHO: primeiro degrau em que a latência mediana passa a ser pelo
	// menos o triplo do primeiro degrau. É a leitura que interessa — não o
	// valor final, e sim ONDE a máquina começou a sofrer.
	if len(degraus) >= 2 {
		base, _ := degraus[0]["latencia_mediana_ms"].(float64)
		if base > 0 {
			for _, d := range degraus[1:] {
				atual, _ := d["latencia_mediana_ms"].(float64)
				if atual >= base*3 {
					saida["joelho_ocupado_mb"] = d["ocupado_mb"]
					saida["joelho_livre_mb"] = d["livre_mb"]
					saida["joelho_latencia_ms"] = atual
					break
				}
			}
		}
	}
	return saida
}

// ---------------------------------------------------------------------------
// Disputa entre processador e memória
// ---------------------------------------------------------------------------

// disputaCPUMemoria mede quanto a banda de memória CAI quando os núcleos estão
// ocupados.
//
// É o exame que separa "processador fraco" de "processador esperando memória".
// Numa máquina de canal único, ou com vídeo integrado disputando o mesmo
// barramento, a banda desaba sob carga enquanto cada peça, medida sozinha,
// parece saudável — e o usuário sente lentidão que nenhum teste isolado
// explica.
func disputaCPUMemoria(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	progress(15, "Medindo banda de memória em repouso")
	repouso, err := bandaDeMemoria(ctx, func(int, string) {})
	if err != nil {
		return map[string]any{}, err
	}

	parar := make(chan struct{})
	ocupantes := runtime.NumCPU() - 1
	if ocupantes < 1 {
		ocupantes = 1
	}
	for n := 0; n < ocupantes; n++ {
		go func() {
			var x uint64 = 1
			for {
				select {
				case <-parar:
					return
				default:
					for i := 0; i < 50000; i++ {
						x = x*6364136223846793005 + 1442695040888963407
					}
				}
			}
		}()
	}

	progress(55, fmt.Sprintf("Medindo banda com %d núcleos ocupados", ocupantes))
	sobCarga, cargaErr := bandaDeMemoria(ctx, func(int, string) {})
	close(parar)
	if cargaErr != nil {
		return map[string]any{}, cargaErr
	}

	livre, _ := repouso["gb_por_segundo"].(float64)
	comCarga, _ := sobCarga["gb_por_segundo"].(float64)
	queda := 0.0
	if livre > 0 {
		queda = (livre - comCarga) / livre * 100
	}

	return map[string]any{
		"banda_em_repouso_gbps": livre,
		"banda_sob_carga_gbps":  comCarga,
		"queda_pct":             arredondar(queda, 1),
		"nucleos_ocupados":      ocupantes,
	}, nil
}

// ---------------------------------------------------------------------------
// Apoio
// ---------------------------------------------------------------------------

type latencias struct{ mediana, p95, pior float64 }

// latenciaDeLeitura mede leituras pequenas espalhadas pelo disco físico.
//
// Espalhadas de propósito: leitura sequencial é servida pelo cache e mediria o
// cache, não o disco. Paginação é acesso aleatório, então é assim que se mede
// o que a paginação vai encontrar.
func latenciaDeLeitura(arquivo interface {
	ReadAt([]byte, int64) (int, error)
}, tamanho uint64, buffer []byte, amostras int) latencias {
	if tamanho == 0 || amostras <= 0 {
		return latencias{}
	}
	valores := make([]float64, 0, amostras)
	passo := tamanho / uint64(amostras+1)
	passo -= passo % 4096
	if passo == 0 {
		passo = 4096
	}
	for i := 1; i <= amostras; i++ {
		posicao := int64(passo * uint64(i))
		inicio := time.Now()
		if _, err := arquivo.ReadAt(buffer, posicao); err != nil {
			continue
		}
		valores = append(valores, float64(time.Since(inicio).Microseconds())/1000)
	}
	if len(valores) == 0 {
		return latencias{}
	}
	sort.Float64s(valores)
	return latencias{
		mediana: mediana(valores),
		p95:     percentilOrdenado(valores, 0.95),
		pior:    valores[len(valores)-1],
	}
}

func mediana(ordenado []float64) float64 {
	if len(ordenado) == 0 {
		return 0
	}
	meio := len(ordenado) / 2
	if len(ordenado)%2 == 1 {
		return ordenado[meio]
	}
	return (ordenado[meio-1] + ordenado[meio]) / 2
}

func percentilOrdenado(ordenado []float64, p float64) float64 {
	if len(ordenado) == 0 {
		return 0
	}
	indice := int(math.Ceil(p*float64(len(ordenado)))) - 1
	if indice < 0 {
		indice = 0
	}
	if indice >= len(ordenado) {
		indice = len(ordenado) - 1
	}
	return ordenado[indice]
}

func arredondar(v float64, casas int) float64 {
	fator := math.Pow(10, float64(casas))
	return math.Round(v*fator) / fator
}

// abrirDiscoPrincipal devolve o primeiro disco físico aberto para leitura.
func abrirDiscoPrincipal(ctx context.Context) (*os.File, uint64, error) {
	cmd := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
		"@(Get-CimInstance Win32_DiskDrive | Select-Object DeviceID,@{n='Size';e={[uint64]$_.Size}}) | ConvertTo-Json -Compress")
	saida, err := cmd.Output()
	if err != nil {
		return nil, 0, fmt.Errorf("falha ao enumerar discos: %w", err)
	}
	var discos []physicalDisk
	if err := json.Unmarshal(saida, &discos); err != nil {
		var um physicalDisk
		if errUm := json.Unmarshal(saida, &um); errUm != nil {
			return nil, 0, fmt.Errorf("resposta de discos inválida: %w", err)
		}
		discos = []physicalDisk{um}
	}
	for _, d := range discos {
		if d.Size == 0 {
			continue
		}
		aberto, errAbrir := os.Open(d.DeviceID)
		if errAbrir != nil {
			continue
		}
		return aberto, d.Size, nil
	}
	return nil, 0, fmt.Errorf("nenhum disco físico acessível para leitura")
}
