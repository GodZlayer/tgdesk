package corpus

import "sort"

// A taxonomia de defeitos, em código (docs/TAXONOMIA-DE-DEFEITOS.md).
//
// Este arquivo é a FONTE ÚNICA da ontologia. O conjunto de causas de cada
// status, os priors declarados e as condutas saem todos daqui — antes estavam
// espalhados em três mapas que precisavam concordar entre si e não concordavam.
//
// A regra que funda tudo:
//
//	Duas coisas são causas diferentes quando geram CONDUTAS diferentes.
//
// E a correção estrutural que motivou a reescrita: o modelo anterior era uma
// árvore `status -> causas`. A relação real é MUITOS-PARA-MUITOS — disco
// falhando produz lentidão, trava, corrupção e não-inicializa. Forçá-la em
// árvore foi o que fez o conjunto de causas ficar torto, com uma causa grossa
// (`recurso_saturado`) engolindo cinco condutas diferentes.
//
// Aqui a fonte é o PROBLEMA, e cada problema declara quais status produz. O
// conjunto de causas de um status é derivado disso, nunca escrito à mão.

// TipoDeDefeito é o nível 1: o que está errado, em famílias de conduta.
type TipoDeDefeito string

const (
	// Hardware com defeito, progressivo ou súbito. Substituir.
	TipoPecaFalhando TipoDeDefeito = "peca_falhando"
	// Hardware SÃO, aquém da carga. Melhorar ou reduzir a carga.
	//
	// A distinção contra `peca_falhando` é a que mais mexe em dinheiro: uma
	// gera troca urgente com risco de perda de dado, a outra gera upgrade
	// planejado. O discriminador é sempre o mesmo — a peça está fora da
	// especificação, ou dentro dela e a especificação é baixa?
	TipoPecaInsuficiente TipoDeDefeito = "peca_insuficiente"
	// Hardware são e suficiente, operando fora das condições. Manutenção física.
	TipoPecaMalCondicionada TipoDeDefeito = "peca_mal_condicionada"
	// Estado, não peça: espaço, memória, handles. Liberar — e é o tipo de
	// melhor custo-benefício, porque reverte sem tocar em hardware.
	TipoRecursoEsgotado TipoDeDefeito = "recurso_esgotado"
	// Programa, serviço, driver, sistema, malware.
	TipoSoftware TipoDeDefeito = "software"
	// Fora do gabinete: energia, rede, temperatura do ambiente.
	TipoAmbiente TipoDeDefeito = "ambiente_externo"
	// A máquina faz o que ela é; a expectativa é maior. NÃO é conserto.
	//
	// Existe de propósito e é o mais fácil de esquecer. Sem ele um produto de
	// diagnóstico sempre encontra defeito, porque foi construído para isso — e
	// começa a mandar trocar peça sã.
	TipoExpectativa TipoDeDefeito = "expectativa"
)

// Veredito de viabilidade da medida que separa o problema (§13.6).
type Veredito string

const (
	MedidaExiste    Veredito = "existe"    // o agente já mede
	MedidaAdaptar   Veredito = "adaptar"   // mede parcial; falta série ou resolução
	MedidaConstruir Veredito = "construir" // não existe, mas é viável
	MedidaInviavel  Veredito = "inviavel"  // exige presença física ou hardware externo
)

// Problema é o nível 2: uma coisa concreta que pode estar errada.
type Problema struct {
	Codigo string
	Tipo   TipoDeDefeito
	// Como se separa dos vizinhos. É o texto que vira "o teste que mais separa"
	// quando o dossiê não decide (§10.5.1).
	Discriminador string
	// A CONDUTA. É o motivo de o problema existir: se dois problemas têm a
	// mesma conduta, são o mesmo problema.
	Acao string
	// Os sinais do vocabulário que apontam para ele.
	Sinais []string
	// Os status observáveis que ele produz. Muitos-para-muitos, e é daqui que
	// o conjunto de causas de cada status é derivado.
	Produz []string
	// Viabilidade da medida discriminante.
	Medida Veredito
	// Descrição para o técnico e para o cliente (§12.2).
	Tecnico string
	Cliente string
}

// Catalogo é o conjunto FECHADO de problemas.
//
// Ordenado por tipo, e dentro do tipo pela frequência esperada. Cada entrada
// aqui é uma afirmação de que aquilo é separável dos vizinhos e gera conduta
// própria — as duas condições para existir.
var Catalogo = []Problema{
	// --- Tipo 1: peça falhando -------------------------------------------
	{
		Codigo: "disco_degradado", Tipo: TipoPecaFalhando, Medida: MedidaExiste,
		Discriminador: "SMART fora de Healthy, setores realocados ou pendentes, erros de I/O no log",
		Acao:          "fazer backup imediato e substituir o disco",
		Sinais:        []string{"smart_geral", "smart_reallocated", "smart_pending", "erro_io_log"},
		Produz:        []string{"lentidao_profunda", "trava_sob_carga", "corrupcao_de_dados", "nao_inicializa", "erro_de_dispositivo"},
		Tecnico:       "Disco degradado — superfície, controladora ou interface falhando.",
		Cliente:       "O disco (onde ficam seus arquivos) está falhando.",
	},
	{
		Codigo: "disco_desgastado", Tipo: TipoPecaFalhando, Medida: MedidaExiste,
		Discriminador: "vida útil restante do SSD abaixo do limiar, com SMART ainda saudável",
		Acao:          "programar a substituição antes da falha; o disco ainda funciona",
		Sinais:        []string{"smart_desgaste"},
		Produz:        []string{"lentidao_profunda", "erro_de_dispositivo"},
		Tecnico:       "SSD com vida útil consumida — escrita restante abaixo do seguro.",
		Cliente:       "O disco está chegando ao fim da vida útil dele.",
	},
	{
		Codigo: "memoria_instavel", Tipo: TipoPecaFalhando, Medida: MedidaAdaptar,
		Discriminador: "erro de memória no log do sistema, ou falha em teste de memória",
		Acao:          "testar os pentes e substituir o defeituoso",
		Sinais:        []string{"erro_memoria"},
		Produz:        []string{"trava_sob_carga", "desligamento_inesperado", "corrupcao_de_dados", "nao_inicializa"},
		Tecnico:       "Memória instável — erro de leitura/escrita em RAM sob carga.",
		Cliente:       "A memória do computador está com defeito.",
	},
	{
		Codigo: "fonte_falhando", Tipo: TipoPecaFalhando, Medida: MedidaConstruir,
		Discriminador: "queda sob carga, tensão fora de faixa, desligamento SEM registro no log",
		Acao:          "substituir a fonte de alimentação",
		Sinais:        []string{"tensao", "desligamento_subito"},
		Produz:        []string{"desligamento_inesperado", "trava_sob_carga", "nao_inicializa"},
		Tecnico:       "Fonte de alimentação instável sob carga.",
		Cliente:       "A fonte de energia do computador está falhando.",
	},
	{
		Codigo: "bateria_degradada", Tipo: TipoPecaFalhando, Medida: MedidaExiste,
		Discriminador: "capacidade atual muito abaixo da de projeto, contagem de ciclos alta",
		Acao:          "substituir a bateria",
		Sinais:        []string{"bateria"},
		Produz:        []string{"desligamento_inesperado"},
		Tecnico:       "Bateria com capacidade muito abaixo da nominal.",
		Cliente:       "A bateria já não segura carga.",
	},
	{
		Codigo: "gpu_falhando", Tipo: TipoPecaFalhando, Medida: MedidaAdaptar,
		Discriminador: "reinício de driver de vídeo (TDR), artefatos, erro de vídeo no log",
		Acao:          "testar com vídeo alternativo e substituir a placa",
		Sinais:        []string{"driver_falho", "bugcheck"},
		Produz:        []string{"trava_sob_carga", "desligamento_inesperado"},
		Tecnico:       "Placa de vídeo instável — reinícios de driver ou erro de hardware.",
		Cliente:       "A placa de vídeo está com problema.",
	},
	{
		Codigo: "placa_ou_capacitor", Tipo: TipoPecaFalhando, Medida: MedidaInviavel,
		Discriminador: "por exclusão de todo o resto; exige inspeção física",
		Acao:          "inspeção presencial da placa",
		Sinais:        []string{},
		Produz:        []string{"desligamento_inesperado", "nao_inicializa", "trava_sob_carga"},
		Tecnico:       "Suspeita de falha na placa-mãe — não separável à distância.",
		Cliente:       "Pode ser um problema na placa; só dá para saber presencialmente.",
	},

	// --- Tipo 2: peça insuficiente ---------------------------------------
	{
		Codigo: "disco_lento", Tipo: TipoPecaInsuficiente, Medida: MedidaExiste,
		Discriminador: "latência de I/O alta COM SMART saudável — o disco funciona, só é devagar",
		Acao:          "substituir por um disco mais rápido (SSD/NVMe); o atual não tem defeito",
		Sinais:        []string{"latencia_disco"},
		Produz:        []string{"lentidao_profunda"},
		Tecnico:       "Disco funcional porém lento — latência alta com SMART saudável.",
		Cliente:       "O disco funciona, mas é lento para o que você faz.",
	},
	{
		Codigo: "memoria_insuficiente", Tipo: TipoPecaInsuficiente, Medida: MedidaAdaptar,
		Discriminador: "uso de memória sustentado no teto COM paginação, e SEM erro de memória",
		Acao:          "aumentar a memória, ou reduzir o que roda simultaneamente",
		Sinais:        []string{"uso_memoria"},
		Produz:        []string{"lentidao_profunda", "lentidao_intermitente", "trava_sob_carga"},
		Tecnico:       "Memória insuficiente para a carga — uso no teto com paginação.",
		Cliente:       "O computador tem menos memória do que precisa para o que você usa.",
	},
	{
		Codigo: "cpu_insuficiente", Tipo: TipoPecaInsuficiente, Medida: MedidaExiste,
		Discriminador: "uso de CPU sustentado alto SEM pico isolado — é carga contínua, não disputa",
		Acao:          "reduzir a carga, ou trocar o equipamento para o uso pretendido",
		Sinais:        []string{"uso_cpu"},
		Produz:        []string{"lentidao_profunda", "lentidao_intermitente"},
		Tecnico:       "Processador insuficiente para a carga — uso sustentado no teto.",
		Cliente:       "O processador não dá conta do que você usa.",
	},
	{
		Codigo: "rede_insuficiente", Tipo: TipoPecaInsuficiente, Medida: MedidaConstruir,
		Discriminador: "banda disponível abaixo do uso, sem perda nem latência anormal",
		Acao:          "contratar banda maior ou redistribuir o uso",
		Sinais:        []string{},
		Produz:        []string{"lentidao_profunda"},
		Tecnico:       "Banda de rede abaixo do necessário para o uso.",
		Cliente:       "A internet contratada é menor do que o uso pede.",
	},

	// --- Tipo 3: peça mal condicionada -----------------------------------
	{
		Codigo: "refrigeracao_insuficiente", Tipo: TipoPecaMalCondicionada, Medida: MedidaExiste,
		Discriminador: "temperatura alta COM carga normal; throttling térmico",
		Acao:          "limpar e revisar a refrigeração (pasta térmica, poeira, fluxo de ar)",
		Sinais:        []string{"temperatura", "ventoinha"},
		Produz:        []string{"superaquecimento", "lentidao_intermitente", "trava_sob_carga", "desligamento_inesperado"},
		Tecnico:       "Refrigeração insuficiente — dissipação abaixo do necessário para a carga.",
		Cliente:       "O computador está esquentando demais.",
	},
	{
		Codigo: "mau_contato", Tipo: TipoPecaMalCondicionada, Medida: MedidaInviavel,
		Discriminador: "erros intermitentes que somem ao reassentar peça ou trocar cabo",
		Acao:          "reassentar peças e substituir cabos — exige mão na máquina",
		Sinais:        []string{"erro_io_log"},
		Produz:        []string{"erro_de_dispositivo", "trava_sob_carga", "nao_inicializa"},
		Tecnico:       "Suspeita de mau contato ou cabo — não separável à distância.",
		Cliente:       "Pode ser mau contato; só dá para verificar presencialmente.",
	},

	// --- Tipo 4: recurso esgotado ----------------------------------------
	{
		Codigo: "disco_cheio", Tipo: TipoRecursoEsgotado, Medida: MedidaExiste,
		Discriminador: "ocupação acima de 90%, sem folga para paginação e temporários",
		Acao:          "liberar espaço; abaixo de 10% livre o sistema não tem folga para trabalhar",
		Sinais:        []string{"processo_pesado"},
		Produz:        []string{"lentidao_profunda", "lentidao_intermitente", "nao_inicializa", "erro_de_dispositivo"},
		Tecnico:       "Disco sem espaço livre — sem folga para paginação, cache e temporários.",
		Cliente:       "O disco está quase cheio, e isso deixa tudo mais devagar.",
	},
	{
		Codigo: "processo_em_segundo_plano", Tipo: TipoRecursoEsgotado, Medida: MedidaConstruir,
		Discriminador: "um processo identificável consumindo o recurso durante o episódio",
		Acao:          "identificar o processo e controlar horário, configuração ou remoção",
		Sinais:        []string{"processo_pesado"},
		Produz:        []string{"lentidao_intermitente", "lentidao_profunda"},
		Tecnico:       "Processo ou serviço em segundo plano consumindo recurso.",
		Cliente:       "Um programa trabalhando escondido está consumindo o computador.",
	},

	// --- Tipo 5: software / configuração ---------------------------------
	{
		Codigo: "software_conflitante", Tipo: TipoSoftware, Medida: MedidaAdaptar,
		Discriminador: "programa ou serviço que interfere; falha de serviço no log",
		Acao:          "remover ou reconfigurar o programa que interfere",
		Sinais:        []string{"servico_caiu", "erro_sistema_log"},
		Produz:        []string{"lentidao_intermitente", "trava_sob_carga", "desligamento_inesperado"},
		Tecnico:       "Software conflitante — programa ou serviço interferindo no sistema.",
		Cliente:       "Um programa instalado está atrapalhando o sistema.",
	},
	{
		Codigo: "driver_incompativel", Tipo: TipoSoftware, Medida: MedidaAdaptar,
		Discriminador: "código de erro de driver, bugcheck atribuído a driver",
		Acao:          "atualizar ou reverter o driver",
		Sinais:        []string{"driver_falho", "bugcheck"},
		Produz:        []string{"desligamento_inesperado", "trava_sob_carga", "lentidao_intermitente"},
		Tecnico:       "Driver incompatível ou defeituoso para o hardware presente.",
		Cliente:       "Um programa de controle de peça está com defeito.",
	},
	{
		Codigo: "sistema_corrompido", Tipo: TipoSoftware, Medida: MedidaAdaptar,
		Discriminador: "verificação de integridade com erro, evento de corrupção no log",
		Acao:          "reparar a integridade do sistema; reinstalar se não reparar",
		Sinais:        []string{"corrupcao_arquivo"},
		Produz:        []string{"nao_inicializa", "corrupcao_de_dados", "trava_sob_carga"},
		Tecnico:       "Sistema de arquivos ou componentes do sistema corrompidos.",
		Cliente:       "Arquivos do sistema estão danificados.",
	},
	{
		Codigo: "inicializacao_pesada", Tipo: TipoSoftware, Medida: MedidaExiste,
		Discriminador: "muitos itens de inicialização, tempo de boot alto",
		Acao:          "reduzir os programas que sobem junto com o sistema",
		Sinais:        []string{"processo_pesado"},
		Produz:        []string{"lentidao_intermitente"},
		Tecnico:       "Inicialização carregada — muitos programas subindo com o sistema.",
		Cliente:       "Muita coisa abre sozinha quando o computador liga.",
	},

	// --- Tipo 6: ambiente externo ----------------------------------------
	{
		Codigo: "alimentacao_instavel", Tipo: TipoAmbiente, Medida: MedidaAdaptar,
		Discriminador: "desligamento sem bugcheck, evento de energia; afeta também outros equipamentos",
		Acao:          "verificar rede elétrica, estabilizador e nobreak",
		Sinais:        []string{"desligamento_subito", "tensao"},
		Produz:        []string{"desligamento_inesperado", "nao_inicializa"},
		Tecnico:       "Alimentação externa instável — rede elétrica fora da faixa.",
		Cliente:       "A energia que chega ao computador está oscilando.",
	},
	{
		Codigo: "ambiente_quente", Tipo: TipoAmbiente, Medida: MedidaExiste,
		Discriminador: "temperatura alta em TODAS as peças, inclusive em repouso",
		Acao:          "melhorar a ventilação do ambiente onde a máquina fica",
		Sinais:        []string{"temperatura"},
		Produz:        []string{"superaquecimento", "lentidao_intermitente"},
		Tecnico:       "Temperatura do ambiente acima do adequado para o equipamento.",
		Cliente:       "O lugar onde o computador fica está quente demais.",
	},
	{
		Codigo: "rede_instavel", Tipo: TipoAmbiente, Medida: MedidaExiste,
		Discriminador: "perda e latência no enlace; aparece além do gateway",
		Acao:          "verificar enlace, cabo, wi-fi e provedor",
		Sinais:        []string{},
		Produz:        []string{"lentidao_profunda", "lentidao_intermitente"},
		Tecnico:       "Rede instável — perda, latência ou saturação do enlace.",
		Cliente:       "A conexão de rede está instável.",
	},

	// --- Tipo 7: expectativa ---------------------------------------------
	{
		Codigo: "dentro_do_esperado", Tipo: TipoExpectativa, Medida: MedidaConstruir,
		Discriminador: "todas as medidas dentro da faixa esperada para a classe do equipamento",
		Acao:          "não há defeito; conversar sobre dimensionamento para o uso pretendido",
		Sinais:        []string{},
		Produz:        []string{"lentidao_profunda", "lentidao_intermitente"},
		Tecnico:       "Equipamento operando dentro do esperado para a classe dele.",
		Cliente:       "O computador está funcionando como o esperado para o que ele é.",
	},
}

// porCodigo indexa o catálogo. Construído uma vez.
var porCodigo = func() map[string]Problema {
	m := make(map[string]Problema, len(Catalogo))
	for _, p := range Catalogo {
		m[p.Codigo] = p
	}
	return m
}()

// ProblemaPorCodigo devolve a entrada do catálogo.
func ProblemaPorCodigo(codigo string) (Problema, bool) {
	p, ok := porCodigo[codigo]
	return p, ok
}

// StatusIndeterminado é o estado em que se sabe QUE está lento e não se sabe a
// FORMA do episódio — engasgo curto contra degradação sustentada.
//
// Não é um status como os outros: nenhum problema o "produz". Ele é o que
// sobra enquanto a medida que separa os dois não existe, e por isso admite a
// UNIÃO das causas dos dois. Deixá-lo sem causa nenhuma faria o motor
// responder "catálogo não revisado", que é uma mensagem errada para uma
// situação legítima — a de não ter medido ainda.
const StatusIndeterminado = "lentidao_nao_caracterizada"

var statusUnidosPeloIndeterminado = []string{"lentidao_intermitente", "lentidao_profunda"}

// CausasDoStatus deriva, do catálogo, quais problemas produzem um status.
//
// É a inversão da matriz: o catálogo declara `Produz`, e daqui sai o conjunto
// de causas candidatas. Escrever esse conjunto à mão em outro lugar era o que
// permitia os dois discordarem — e discordavam.
func CausasDoStatus(status string) []string {
	if status == StatusIndeterminado {
		visto := map[string]bool{}
		var uniao []string
		for _, s := range statusUnidosPeloIndeterminado {
			for _, c := range CausasDoStatus(s) {
				if !visto[c] {
					visto[c] = true
					uniao = append(uniao, c)
				}
			}
		}
		sort.Strings(uniao)
		return uniao
	}
	var causas []string
	for _, p := range Catalogo {
		for _, s := range p.Produz {
			if s == status {
				causas = append(causas, p.Codigo)
				break
			}
		}
	}
	sort.Strings(causas)
	return causas
}

// SinaisDoStatus devolve todos os sinais que os problemas daquele status usam.
func SinaisDoStatus(status string) []string {
	visto := map[string]bool{}
	for _, codigo := range CausasDoStatus(status) {
		for _, s := range porCodigo[codigo].Sinais {
			visto[s] = true
		}
	}
	out := make([]string, 0, len(visto))
	for s := range visto {
		out = append(out, s)
	}
	sort.Strings(out)
	return out
}

// LacunasDoStatus lista as causas daquele status que NÃO são separáveis à
// distância. Aparecem na tela como limitação declarada, em vez de sumirem
// (§13.6) — uma causa que existe e não é separável precisa estar visível.
func LacunasDoStatus(status string) []string {
	var lacunas []string
	for _, codigo := range CausasDoStatus(status) {
		if porCodigo[codigo].Medida == MedidaInviavel {
			lacunas = append(lacunas, codigo)
		}
	}
	sort.Strings(lacunas)
	return lacunas
}

// StatusConhecidos devolve todo status que algum problema produz.
func StatusConhecidos() []string {
	visto := map[string]bool{StatusIndeterminado: true}
	for _, p := range Catalogo {
		for _, s := range p.Produz {
			visto[s] = true
		}
	}
	out := make([]string, 0, len(visto))
	for s := range visto {
		out = append(out, s)
	}
	sort.Strings(out)
	return out
}
