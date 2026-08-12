package corpus

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Extração de MEDIDAS dos blocos de log (§19.1 da arquitetura).
//
// A diferença entre este arquivo e `derivacao.go` é a diferença entre relato e
// exame. Lá se extrai vocabulário — "o disco está lento" vira o sinal
// `latencia_disco`. Aqui se extrai valor: `Event ID 41`, `0x0000007A`,
// `Reallocated_Sector_Ct 12`, `97 °C`. Com unidade, no mesmo formato que o
// agente coleta.
//
// É isso que transforma uma thread de fórum em exemplo de treino: um caso com
// medida tem ENTRADA (os valores) e SAÍDA (a causa que os humanos confirmaram).
//
// REGRA QUE NÃO SE NEGOCIA (§19.3): nada aqui inventa valor. O que se produz é
// o formato; o número vem do log. Onde o caso não disser, o campo fica AUSENTE
// — e ausência é informação, não é zero. Um extrator que preenche lacuna com
// zero ensina a rede que "sem dado" e "dado zerado" são a mesma coisa, e são
// exatamente opostos.

// Medida é um valor literal encontrado num log, já normalizado.
type Medida struct {
	// Campo no formato do dossiê: 'evento_sistema', 'bugcheck', 'smart',
	// 'temperatura', 'kernel_panic'.
	Campo string
	// Chave dentro do campo: o Event ID, o nome do bugcheck, o atributo SMART.
	Chave string
	// Valor numérico quando existe. Nulo quando a medida é categórica —
	// e nulo é diferente de zero.
	Valor   *float64
	Unidade string
	// A linha literal de onde saiu. É o que aparece na tela como evidência
	// citável (§8) e o que permite auditar a extração.
	Literal string
	// Gravidade declarada pelo próprio log ('Error', 'Warning', 'Critical').
	Nivel string
}

var (
	// Formato do Visualizador de Eventos do Windows, que é o que mais aparece
	// nos casos reais: blocos com Source, Event ID e Level.
	reEventoLinha = regexp.MustCompile(`(?is)Log Name:\s*(\S+).{0,200}?Source:\s*([^\s]+).{0,300}?Event ID:\s*(\d+).{0,200}?Level:\s*(\w+)`)
	// Forma curta, também comum: "Event ID 51" solto no texto.
	reEventoCurto = regexp.MustCompile(`(?i)\bEvent ID:?\s*(\d{1,5})\b`)

	// Bugcheck: nome simbólico e/ou código hexadecimal.
	reBugcheckNome = regexp.MustCompile(`\b([A-Z][A-Z0-9_]{6,50})\s*\(\s*(0x)?([0-9a-fA-F]{6,8})\s*\)`)
	// Código hexadecimal SÓ quando uma palavra o qualifica. Sem isso, todo dump
	// de registradores vira bugcheck: `CR0: 0x00000000` casava, e a medida mais
	// frequente do corpus inteiro passou a ser `0x00000000` — que não é código
	// de parada nenhum, é registrador zerado.
	reBugcheckHex = regexp.MustCompile(`(?i)(?:bugcheck|stop\s*(?:code|error)?|bsod|check\s*string)[^\n]{0,40}?\b(?:0x)?0{0,4}([0-9a-fA-F]{1,8})\b`)

	// Atributos SMART no formato do smartctl/CrystalDiskInfo.
	// Captura a LINHA inteira depois do atributo, porque o valor que interessa
	// é o RAW_VALUE — a ÚLTIMA coluna, não a primeira. Pegar o primeiro número
	// devolveria o flag `0x0033` ou o VALUE normalizado (quase sempre 100), e
	// um disco com 12 setores realocados apareceria como zero.
	reSmart        = regexp.MustCompile(`(?i)\b(Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable|Reported_Uncorrect|UDMA_CRC_Error_Count|Power_On_Hours|Wear_Leveling_Count)\b([^\n]{0,120})`)
	reUltimoNumero = regexp.MustCompile(`(\d+)\D*$`)

	// Temperatura com unidade explícita.
	reTemperatura = regexp.MustCompile(`(?i)\b(\d{2,3})\s*(?:°\s*)?(?:c|celsius)\b`)

	// Kernel panic (macOS/Linux) — categórico, sem valor numérico.
	rePanic = regexp.MustCompile(`(?i)\bpanic\(cpu \d+|kernel panic|BUG: unable to handle`)

	// Erros de boot loader.
	reGrub = regexp.MustCompile(`(?i)\b(grub|error:.{0,40}\.pf2|no such partition|unknown filesystem)\b`)
)

// Nomes de bugcheck que aparecem como palavra solta e não são bugcheck. Sem
// esta lista, `SYSTEM_THREAD_EXCEPTION` casaria junto com títulos de seção do
// próprio depurador.
var naoSaoBugcheck = map[string]bool{
	"BUGCHECK_ANALYSIS": true,
	"BUGCHECK_STR":      true,
	"MODULE_NAME":       true,
	"IMAGE_NAME":        true,
	"FAILURE_BUCKET_ID": true,
	"PROCESS_NAME":      true,
	"DEFAULT_BUCKET_ID": true,
	"MACHINE_ID":        true,
	"BIOS_VERSION":      true,
	"BIOS_VENDOR":       true,
}

// ExtrairMedidas lê um bloco de log e devolve o que ele mede.
//
// Devolve vazio quando não há medida — e isso é resposta legítima: muito bloco
// de log é ruído de console sem valor diagnóstico, e forçá-lo a render alguma
// coisa seria fabricar dado.
func ExtrairMedidas(bloco string) []Medida {
	var saida []Medida
	vistos := map[string]bool{}

	adicionar := func(m Medida) {
		chave := m.Campo + "/" + m.Chave
		if vistos[chave] {
			return
		}
		vistos[chave] = true
		saida = append(saida, m)
	}

	// 1. Eventos do Windows com bloco completo — a forma mais rica: traz fonte
	// e nível declarados pelo próprio sistema (§7.3: se o sistema já diz, não
	// se adivinha).
	for _, m := range reEventoLinha.FindAllStringSubmatch(bloco, -1) {
		id, _ := strconv.ParseFloat(m[3], 64)
		adicionar(Medida{
			Campo:   "evento_sistema",
			Chave:   strings.TrimSpace(m[2]) + ":" + m[3],
			Valor:   &id,
			Unidade: "event_id",
			Nivel:   strings.TrimSpace(m[4]),
			Literal: trecho(m[0]),
		})
	}
	// 2. Forma curta, quando não veio o bloco inteiro.
	if len(saida) == 0 {
		for _, m := range reEventoCurto.FindAllStringSubmatch(bloco, -1) {
			id, _ := strconv.ParseFloat(m[1], 64)
			adicionar(Medida{
				Campo:   "evento_sistema",
				Chave:   "desconhecido:" + m[1],
				Valor:   &id,
				Unidade: "event_id",
				Literal: trecho(m[0]),
			})
		}
	}

	// 3. Bugcheck com nome e código.
	for _, m := range reBugcheckNome.FindAllStringSubmatch(bloco, -1) {
		nome := m[1]
		if naoSaoBugcheck[nome] {
			continue
		}
		adicionar(Medida{
			Campo:   "bugcheck",
			Chave:   nome,
			Unidade: "codigo",
			Literal: trecho(m[0]),
		})
	}
	// 4. Só o código hexadecimal, e só quando qualificado por contexto.
	for _, m := range reBugcheckHex.FindAllStringSubmatch(bloco, -1) {
		codigo, err := strconv.ParseUint(m[1], 16, 32)
		// Códigos de parada do Windows começam em 0x0A. Abaixo disso é
		// registrador, índice de CPU ou contador — nunca causa.
		if err != nil || codigo < 0x0A {
			continue
		}
		adicionar(Medida{
			Campo:   "bugcheck",
			Chave:   fmt.Sprintf("0x%08X", codigo),
			Unidade: "codigo",
			Literal: trecho(m[0]),
		})
	}

	// 5. SMART — o sinal mais discriminante que a derivação encontrou.
	for _, m := range reSmart.FindAllStringSubmatch(bloco, -1) {
		ultimo := reUltimoNumero.FindStringSubmatch(strings.TrimRight(m[2], " 	"))
		if ultimo == nil {
			continue
		}
		v, err := strconv.ParseFloat(ultimo[1], 64)
		if err != nil {
			continue
		}
		valor := v
		adicionar(Medida{
			Campo:   "smart",
			Chave:   canonizarSmart(m[1]),
			Valor:   &valor,
			Unidade: "contagem",
			Literal: trecho(m[0]),
		})
	}

	// 6. Temperatura. Faixa sanitária: abaixo de 30 °C não é leitura de carga e
	// acima de 130 °C não é temperatura de componente — é número solto com um
	// "c" ao lado.
	for _, m := range reTemperatura.FindAllStringSubmatch(bloco, -1) {
		v, err := strconv.ParseFloat(m[1], 64)
		if err != nil || v < 30 || v > 130 {
			continue
		}
		valor := v
		adicionar(Medida{
			Campo:   "temperatura",
			Chave:   "max_observada",
			Valor:   &valor,
			Unidade: "°C",
			Literal: trecho(m[0]),
		})
	}

	// 7. Categóricos, sem valor numérico.
	if rePanic.MatchString(bloco) {
		adicionar(Medida{Campo: "kernel_panic", Chave: "panic", Literal: trecho(bloco)})
	}
	if reGrub.MatchString(bloco) {
		adicionar(Medida{Campo: "boot_loader", Chave: "erro", Literal: trecho(bloco)})
	}

	sort.Slice(saida, func(a, b int) bool {
		if saida[a].Campo != saida[b].Campo {
			return saida[a].Campo < saida[b].Campo
		}
		return saida[a].Chave < saida[b].Chave
	})
	return saida
}

func canonizarSmart(atributo string) string {
	switch strings.ToLower(atributo) {
	case "reallocated_sector_ct":
		return "reallocated"
	case "current_pending_sector":
		return "pending"
	case "offline_uncorrectable", "reported_uncorrect":
		return "uncorrectable"
	case "udma_crc_error_count":
		return "crc"
	case "power_on_hours":
		return "horas_ligado"
	case "wear_leveling_count":
		return "desgaste"
	}
	return strings.ToLower(atributo)
}

// trecho corta o literal para caber na tela como evidência citável, sem perder
// a linha que decidiu.
func trecho(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > 180 {
		return s[:180] + "…"
	}
	return s
}

// CasoReal é o que §19.1 define: sintoma + medidas + causa confirmada.
//
// É a unidade que parametriza a escada (§19.2) e que vira exemplo de treino
// por simulação (§19.3).
type CasoReal struct {
	ThreadID string
	Sintoma  string
	Classe   string
	Medidas  []Medida
	// Causa confirmada pelos humanos. É o rótulo do exemplo de treino: o alvo
	// é a rede chegar ao mesmo desfecho.
	CausaConfirmada string
	// Sinais em vocabulário, para cruzar com a derivação de §13.6.
	Sinais []string
	Testes []string
}

// TemMedida diz se o caso serve como exemplo de treino. Caso sem medida
// continua valendo como vocabulário, mas não vira dossiê sintético — não há o
// que sintetizar.
func (c CasoReal) TemMedida() bool { return len(c.Medidas) > 0 }

// CamposDoDossie lista os campos que este caso preenche. É a ponte de §19.2:
// o conjunto dessas listas, sobre todos os casos, É a telemetria necessária —
// em vez de alguém decidir por intuição o que o agente deve medir.
func (c CasoReal) CamposDoDossie() []string {
	vistos := map[string]bool{}
	var campos []string
	for _, m := range c.Medidas {
		if !vistos[m.Campo] {
			vistos[m.Campo] = true
			campos = append(campos, m.Campo)
		}
	}
	sort.Strings(campos)
	return campos
}
