package corpus

import (
	"math"
	"sort"
	"strings"
)

// Derivação: do corpus para a ontologia (§13.6, trilhas A3 e A4).
//
// Inverte a ordem causal do projeto. Não se parte do que o agente já sabe
// medir; parte-se do que os casos reais exigiram para serem resolvidos. O que
// sai daqui é: quais SINAIS precisam existir, quais TESTES discriminam, e o
// quanto o catálogo atual cobre — por classe de problema, nunca em agregado.
//
// O que este arquivo NÃO faz: decidir. Tudo o que ele produz é rascunho com
// contagem, para revisão humana. Nada entra em `negative_status` ou
// `log_signature` sem `revisado_por` preenchido (§8, §12.3).

// Vocabulário diagnóstico. Cada entrada é um sinal observável com as formas em
// que humanos o escrevem — em inglês, porque a fonte é o Superuser, e em
// português, porque as próximas fontes serão.
//
// Esta lista é o ponto de partida da passagem 1 (extração), não a resposta: a
// frequência é que dirá o que fica. Sinal que nenhum caso citou sai na poda
// (passagem 4), e sinal que os casos exigiram e não está aqui aparece como
// buraco quando a cobertura de uma classe vier baixa.
var vocabularioDeSinais = map[string][]string{
	"smart_reallocated":   {"reallocated sector", "reallocated_sector", "setores realocados", "realocado"},
	"smart_pending":       {"pending sector", "current pending", "setor pendente"},
	"smart_geral":         {"smart status", "smart attribute", "crystaldiskinfo", "smartctl", "smart data"},
	"erro_io_log":         {"bad block", "disk error", "event id 51", "event id 7", "controller error", "i/o error", "erro de leitura"},
	"latencia_disco":      {"disk latency", "100% disk", "disk usage 100", "response time", "disco em 100"},
	"erro_memoria":        {"memtest", "memory error", "erro de memória", "erro de memoria", "page fault", "memory_management"},
	"uso_memoria":         {"out of memory", "memory usage", "committed memory", "memória cheia", "ram usage"},
	"temperatura":         {"temperature", "overheat", "thermal throttl", "°c", " celsius", "temperatura", "hwmonitor", "core temp"},
	"ventoinha":           {"fan speed", "fan noise", "ventoinha", "cooler"},
	"desligamento_subito": {"unexpected shutdown", "kernel-power", "event id 41", "desligou sozinho", "shuts down suddenly"},
	"bugcheck":            {"bugcheck", "bsod", "blue screen", "stop code", "0x0000", "minidump", "tela azul"},
	"tensao":              {"voltage", "psu", "power supply", "12v", "tensão", "fonte de alimentação"},
	"bateria":             {"battery health", "battery wear", "saúde da bateria", "ciclos da bateria"},
	"driver_falho":        {"driver error", "code 43", "driver crash", "dxgkrnl", "driver desatualizado"},
	"servico_caiu":        {"service failed", "service crashed", "serviço parou"},
	"uso_cpu":             {"cpu usage", "100% cpu", "high cpu", "uso de cpu"},
	"processo_pesado":     {"task manager", "gerenciador de tarefas", "process using", "processo consumindo"},
	"erro_sistema_log":    {"event viewer", "visualizador de eventos", "system log", "log do sistema"},
	"corrupcao_arquivo":   {"chkdsk", "sfc /scannow", "dism", "file system corrupt", "sistema de arquivos"},
	"boot_falho":          {"boot loop", "no post", "won't boot", "não dá boot", "nao da boot", "beep code"},
}

// Testes que os humanos mandam rodar. Serve à passagem 2: um teste que aparece
// em muitos casos e separa bem é essencial; o que aparece pouco é dispensável.
var vocabularioDeTestes = map[string][]string{
	"memtest":          {"memtest", "memtest86", "windows memory diagnostic", "mdsched"},
	"smart_leitura":    {"crystaldiskinfo", "smartctl", "smart status", "hd tune", "hdtune"},
	"superficie_disco": {"chkdsk /r", "surface scan", "badblocks", "hd sentinel"},
	"stress_cpu":       {"prime95", "aida64", "occt", "cinebench", "stress test"},
	"stress_gpu":       {"furmark", "3dmark", "heaven benchmark"},
	"leitura_termica":  {"hwmonitor", "core temp", "hwinfo", "speedfan"},
	"benchmark_disco":  {"crystaldiskmark", "atto", "hd tach"},
	"integridade_so":   {"sfc /scannow", "dism /online", "chkdsk"},
	"boot_limpo":       {"clean boot", "safe mode", "msconfig", "modo de segurança"},
	"troca_peca":       {"swap the", "try another", "test with a different", "troque", "teste com outro"},
	"leitura_eventos":  {"event viewer", "eventvwr", "get-winevent", "visualizador de eventos"},
}

// ExtrairSinais devolve os sinais citados num texto, sem repetição.
func ExtrairSinais(texto string) []string {
	return casarVocabulario(texto, vocabularioDeSinais)
}

// ExtrairTestes devolve os testes citados num texto.
func ExtrairTestes(texto string) []string {
	return casarVocabulario(texto, vocabularioDeTestes)
}

func casarVocabulario(texto string, vocab map[string][]string) []string {
	t := strings.ToLower(texto)
	var achados []string
	for chave, formas := range vocab {
		for _, f := range formas {
			if strings.Contains(t, f) {
				achados = append(achados, chave)
				break
			}
		}
	}
	sort.Strings(achados)
	return achados
}

// CasoDerivado é o que a passagem 1 extrai de cada caso resolvido.
type CasoDerivado struct {
	ThreadID string
	Classe   string
	// Sinais e testes citados na MENSAGEM CAUSAL — não na thread inteira. O que
	// o autor tentou antes e não resolveu não é evidência da causa; é ruído com
	// aparência de evidência.
	Sinais []string
	Testes []string
}

// DemandaDeSinal é o resultado das passagens 2 e 3 para um sinal (§13.6).
type DemandaDeSinal struct {
	Sinal              string
	CasosQueExigiram   int
	ClassesQueConsomem []string
	// GanhoDeInformacao mede o quanto o sinal SEPARA classes, não o quanto ele
	// aparece. Um sinal presente em todo caso de toda classe é frequente e
	// inútil: não muda a probabilidade de nada.
	GanhoDeInformacao float64
}

// AgregarDemanda executa a passagem 2: frequência de cada sinal por classe, e o
// quanto ele discrimina.
func AgregarDemanda(casos []CasoDerivado) []DemandaDeSinal {
	porSinal := map[string]map[string]int{}
	totalPorSinal := map[string]int{}

	for _, c := range casos {
		for _, s := range c.Sinais {
			if porSinal[s] == nil {
				porSinal[s] = map[string]int{}
			}
			porSinal[s][c.Classe]++
			totalPorSinal[s]++
		}
	}

	saida := make([]DemandaDeSinal, 0, len(porSinal))
	for sinal, porClasse := range porSinal {
		classes := make([]string, 0, len(porClasse))
		for c := range porClasse {
			classes = append(classes, c)
		}
		sort.Strings(classes)
		saida = append(saida, DemandaDeSinal{
			Sinal:              sinal,
			CasosQueExigiram:   totalPorSinal[sinal],
			ClassesQueConsomem: classes,
			GanhoDeInformacao:  poderDeSeparacao(porClasse, totalPorSinal[sinal]),
		})
	}

	// Mais discriminante primeiro; empate desfeito por frequência. É a ordem em
	// que um humano quer revisar: o que decide mais, primeiro.
	sort.Slice(saida, func(a, b int) bool {
		if saida[a].GanhoDeInformacao != saida[b].GanhoDeInformacao {
			return saida[a].GanhoDeInformacao > saida[b].GanhoDeInformacao
		}
		return saida[a].CasosQueExigiram > saida[b].CasosQueExigiram
	})
	return saida
}

// poderDeSeparacao devolve 1 quando o sinal aparece numa única classe (separa
// perfeitamente) e tende a 0 quando se espalha igualmente por muitas.
//
// É entropia normalizada e invertida. Não é ganho de informação no sentido
// estrito de árvore de decisão — é a versão que se consegue calcular com o que
// o corpus dá, e serve para o que precisa servir: ordenar sinais para revisão
// humana.
func poderDeSeparacao(porClasse map[string]int, total int) float64 {
	if total == 0 || len(porClasse) <= 1 {
		return 1
	}
	var entropia float64
	for _, n := range porClasse {
		p := float64(n) / float64(total)
		if p > 0 {
			entropia -= p * math.Log2(p)
		}
	}
	entropiaMax := math.Log2(float64(len(porClasse)))
	if entropiaMax == 0 {
		return 1
	}
	return 1 - entropia/entropiaMax
}

// Veredito de viabilidade (§13.6, passagem 3).
const (
	VereditoExiste    = "existe"
	VereditoAdaptar   = "adaptar"
	VereditoConstruir = "construir"
	VereditoInviavel  = "inviavel"
)

// Cobertura é o critério de aceite da missão (§13.6), medido POR CLASSE.
type Cobertura struct {
	Classe              string
	CasosTotal          int
	CasosDiscriminaveis int
	Cobertura           float64
	Lacunas             []string
	// CasosSemSinal separa dois buracos que a cobertura crua confunde:
	//
	//   1. o caso citou um sinal que o agente NÃO mede  → lacuna de produto
	//   2. o caso não citou sinal nenhum reconhecível   → lacuna de EXTRAÇÃO
	//
	// Os dois derrubam a cobertura, mas pedem trabalho oposto: o primeiro é
	// backlog de agente, o segundo é vocabulário pobre do nosso extrator.
	// Relatar só o número agregado faria a equipe construir sensor para um
	// problema que era de leitura de texto.
	CasosSemSinal int
	// CoberturaInstrumentada é a fração calculada SÓ sobre os casos em que
	// alguém citou uma medição. É esta que responde a pergunta de §13.6 —
	// "o catálogo conseguiria ter discriminado?" — porque um caso resolvido sem
	// nenhum instrumento citado não tem como dizer que instrumento faltou.
	//
	// As duas convivem de propósito. A crua diz "de tudo que os humanos
	// resolveram, quanto nós pegaríamos"; a instrumentada diz "do que foi
	// decidido por medição, quanto nós medimos". Mostrar só a primeira faria o
	// catálogo parecer inútil; só a segunda esconderia que existe um mundo de
	// casos que nenhuma telemetria resolve.
	CoberturaInstrumentada float64
}

// MedirCobertura responde "detectamos todos os tipos de problema?" com número:
// a fração dos casos resolvidos cujo desfecho o catálogo atual CONSEGUIRIA ter
// discriminado.
//
// `sinaisDisponiveis` são os sinais com veredito `existe` — o que o agente mede
// hoje. Um caso é discriminável se pelo menos um dos sinais que o resolveram
// está disponível; se nenhum estiver, o caso vira lacuna com o nome dos sinais
// que faltaram.
//
// Medir em agregado esconderia uma classe inteira em zero. Por isso a saída é
// uma linha por classe, sempre.
func MedirCobertura(casos []CasoDerivado, sinaisDisponiveis map[string]bool) []Cobertura {
	porClasse := map[string]*Cobertura{}
	faltantes := map[string]map[string]bool{}

	for _, c := range casos {
		cob, existe := porClasse[c.Classe]
		if !existe {
			cob = &Cobertura{Classe: c.Classe}
			porClasse[c.Classe] = cob
			faltantes[c.Classe] = map[string]bool{}
		}
		cob.CasosTotal++

		// Caso resolvido sem sinal nenhum extraído não é discriminável nem
		// lacuna de sinal: é lacuna de EXTRAÇÃO, e conta contra a cobertura
		// porque, do ponto de vista do produto, aquele caso não seria resolvido.
		discriminavel := false
		for _, s := range c.Sinais {
			if sinaisDisponiveis[s] {
				discriminavel = true
				break
			}
		}
		if discriminavel {
			cob.CasosDiscriminaveis++
			continue
		}
		if len(c.Sinais) == 0 {
			cob.CasosSemSinal++
			continue
		}
		for _, s := range c.Sinais {
			faltantes[c.Classe][s] = true
		}
	}

	saida := make([]Cobertura, 0, len(porClasse))
	for classe, cob := range porClasse {
		if cob.CasosTotal > 0 {
			cob.Cobertura = float64(cob.CasosDiscriminaveis) / float64(cob.CasosTotal)
		}
		if instrumentados := cob.CasosTotal - cob.CasosSemSinal; instrumentados > 0 {
			cob.CoberturaInstrumentada = float64(cob.CasosDiscriminaveis) / float64(instrumentados)
		}
		for s := range faltantes[classe] {
			cob.Lacunas = append(cob.Lacunas, s)
		}
		sort.Strings(cob.Lacunas)
		saida = append(saida, *cob)
	}
	// Pior cobertura primeiro: é onde o trabalho está.
	sort.Slice(saida, func(a, b int) bool {
		if saida[a].Cobertura != saida[b].Cobertura {
			return saida[a].Cobertura < saida[b].Cobertura
		}
		return saida[a].Classe < saida[b].Classe
	})
	return saida
}

// Podar executa a passagem 4: sai do fluxo principal o que nenhum caso usou
// para decidir. Carregar dado que não muda probabilidade é custo puro.
//
// `minimoDeCasos` é o piso de evidência para um sinal continuar. Devolve os que
// ficam e os que saem, separados — a poda é registrada, não silenciosa.
func Podar(demanda []DemandaDeSinal, minimoDeCasos int) (ficam, saem []DemandaDeSinal) {
	for _, d := range demanda {
		if d.CasosQueExigiram >= minimoDeCasos {
			ficam = append(ficam, d)
		} else {
			saem = append(saem, d)
		}
	}
	return ficam, saem
}
