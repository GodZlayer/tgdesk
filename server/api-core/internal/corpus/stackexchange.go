package corpus

import (
	"encoding/xml"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Leitura do dump do Stack Exchange (§13.2).
//
// É a fonte preferida por um motivo estrutural: traz RESPOSTA ACEITA e VOTOS.
// O rótulo é nativo e humano, então não depende da heurística primeira/última —
// que é boa, mas é heurística.
//
// O parser é de fluxo. O `Posts.xml` do Superuser passa de 10 GB descomprimido,
// e materializá-lo em disco ou memória seria trocar um problema de engenharia
// por um problema de máquina. Lê-se elemento a elemento, direto da saída do
// descompressor.
//
// Formato relevante do dump:
//   PostTypeId=1 → pergunta (vira corpus_thread)
//   PostTypeId=2 → resposta (vira corpus_post, ParentId aponta a pergunta)
//   AcceptedAnswerId na pergunta → a resposta que o autor aceitou

// SEPost é uma linha do Posts.xml, só com os campos que interessam. O dump tem
// muito mais atributos; carregar o que não muda probabilidade de causa nenhuma
// seria custo puro (§13.6, poda).
type SEPost struct {
	ID               int
	PostTypeID       int
	ParentID         int
	AcceptedAnswerID int
	OwnerUserID      string
	Title            string
	Body             string
	Tags             string
	Score            int
	CreationDate     time.Time
	AnswerCount      int
}

// LerPosts percorre o Posts.xml e chama `visitar` para cada linha. Devolver
// erro em `visitar` interrompe a leitura.
//
// Não acumula nada: o consumidor decide o que guardar. É o que permite ingerir
// um dump de dezenas de gigabytes com memória constante.
func LerPosts(r io.Reader, visitar func(SEPost) error) error {
	dec := xml.NewDecoder(r)
	// O dump vem em UTF-8, mas traz entidades e caracteres de controle que o
	// decoder estrito recusa. Recusar a linha inteira por causa de um byte
	// perdido descartaria casos bons.
	dec.Strict = false

	for {
		tok, err := dec.Token()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return fmt.Errorf("lendo Posts.xml: %w", err)
		}
		inicio, ok := tok.(xml.StartElement)
		if !ok || inicio.Name.Local != "row" {
			continue
		}
		p, ok := postDeAtributos(inicio.Attr)
		if !ok {
			continue
		}
		if err := visitar(p); err != nil {
			return err
		}
	}
}

func postDeAtributos(attrs []xml.Attr) (SEPost, bool) {
	var p SEPost
	for _, a := range attrs {
		switch a.Name.Local {
		case "Id":
			p.ID, _ = strconv.Atoi(a.Value)
		case "PostTypeId":
			p.PostTypeID, _ = strconv.Atoi(a.Value)
		case "ParentId":
			p.ParentID, _ = strconv.Atoi(a.Value)
		case "AcceptedAnswerId":
			p.AcceptedAnswerID, _ = strconv.Atoi(a.Value)
		case "OwnerUserId":
			p.OwnerUserID = a.Value
		case "Title":
			p.Title = a.Value
		case "Body":
			p.Body = a.Value
		case "Tags":
			p.Tags = a.Value
		case "Score":
			p.Score, _ = strconv.Atoi(a.Value)
		case "AnswerCount":
			p.AnswerCount, _ = strconv.Atoi(a.Value)
		case "CreationDate":
			p.CreationDate, _ = time.Parse("2006-01-02T15:04:05.999", a.Value)
		}
	}
	// Linha sem id ou sem tipo não é linha de post; é lixo de parsing.
	return p, p.ID != 0 && p.PostTypeID != 0
}

// Tags de interesse. O Superuser cobre o domínio-alvo, mas não só ele — há
// muita pergunta de software, rede doméstica e configuração que não produz
// causa de hardware nem status negativo de máquina.
//
// Filtrar na ingestão é deliberado: carregar o corpus inteiro para depois
// descartar significaria pagar por dezenas de gigabytes de texto que nenhuma
// causa consome (§13.6).
var tagsDeInteresse = []string{
	"hardware", "hard-drive", "ssd", "memory", "ram", "cpu", "motherboard",
	"power-supply", "overheating", "temperature", "crash", "freeze", "bsod",
	"boot", "shutdown", "reboot", "performance", "slow", "smart", "hdd",
	"blue-screen-of-death", "kernel-panic", "fan", "gpu", "graphics-card",
	"battery", "laptop", "system-crash", "hang", "disk-failure",
}

// InteressaAoDominio decide se a pergunta entra no corpus. É o primeiro filtro
// de §13.6: sinal que nenhuma causa consome não deveria nem ser ingerido.
//
// O casamento NÃO é por substring solta. "change" contém "hang", "scanner"
// contém "can" — e um filtro assim traria para dentro do corpus de hardware
// toda pergunta de papel de parede. Tag casa como tag inteira; título casa com
// fronteira de palavra.
func InteressaAoDominio(tags, titulo string) bool {
	for _, tag := range tagsDeTexto(tags) {
		for _, alvo := range tagsDeInteresse {
			if tag == alvo {
				return true
			}
		}
	}
	return contemTermo(strings.ToLower(titulo), tagsDeInteresse)
}

// tagsDeTexto separa o formato do dump — "<hard-drive><freeze>" — em tags.
func tagsDeTexto(tags string) []string {
	campo := strings.NewReplacer("<", " ", ">", " ").Replace(strings.ToLower(tags))
	return strings.Fields(campo)
}

// contemTermo casa termo com fronteira de palavra. Aceita termos com hífen
// ("hard-drive"), que é como o Stack Exchange nomeia tag.
func contemTermo(texto string, termos []string) bool {
	for _, termo := range termos {
		// Todas as ocorrências, não só a primeira: "change the fan" tem
		// "hang" em posição ruim e "fan" em posição boa, e parar na primeira
		// descartaria a pergunta.
		for base := 0; ; {
			i := strings.Index(texto[base:], termo)
			if i < 0 {
				break
			}
			i += base
			base = i + 1
			if i > 0 && ehLetraOuDigito(rune(texto[i-1])) {
				continue
			}
			fim := i + len(termo)
			// Plural simples conta: título de fórum diz "my pc hangs", não
			// "my pc hang". Exigir a forma exata perderia o caso comum.
			if fim < len(texto) && texto[fim] == 's' {
				fim++
			}
			if fim >= len(texto) || !ehLetraOuDigito(rune(texto[fim])) {
				return true
			}
		}
	}
	return false
}

func ehLetraOuDigito(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
}

// Pergunta de CONFIGURAÇÃO, não de defeito. O Superuser é, em boa parte, um
// site de "como faço" — e "como instalo o Windows por USB" não tem causa, não
// tem sintoma e não tem diagnóstico. Ingerir isso como caso resolvido
// envenenaria os priors: o modelo aprenderia que a causa de "não dá boot" é
// "particionar o disco".
//
// Descoberto olhando os termos mais frequentes das mensagens causais: "install
// windows", "dual boot", "partition table", "control panel", "secure boot".
var reComoFazer = regexp.MustCompile(`(?i)^\s*(how (to|do|can|would|should)|what('s| is| are)|` +
	`which (is|one|of)|is (there|it possible)|can i|should i|why (is|does|do) .{0,30}\?$|` +
	`where (is|can|do)|difference between|best way|recommend|any way to|` +
	`como (faço|fazer|instalo|configuro)|qual (a|o) (melhor|diferença))`)

// Sinais de que a máquina QUEBROU. Um caso diagnóstico descreve algo que
// deixou de funcionar; uma pergunta de configuração descreve algo que a pessoa
// quer passar a fazer.
//
// Os termos levam sufixo livre (`\w*`) porque a forma que aparece no texto é
// quase sempre flexionada: "freezes", "crashed", "hanging", "failing". Exigir a
// raiz exata com fronteira de palavra descartaria justamente o caso comum — foi
// o que aconteceu no primeiro teste, com "PC freezes under heavy disk load".
var reFalha = regexp.MustCompile(`(?i)\b(crash\w*|freez\w*|frozen|hang\w*|won'?t (boot|start|turn|power|load)|` +
	`not (work\w*|boot\w*|start\w*|respond\w*|detect\w*|recogni\w*)|fail\w*|error\w*|blue ?screen\w*|bsod|` +
	`suddenly|randomly|stopped working|no longer|died|dead|broken|corrupt\w*|` +
	`shuts? down|shutting down|reboots? (itself|randomly)|beep\w*|overheat\w*|slow\w* down|` +
	`travando|travou|trava|não liga|nao liga|parou de funcionar|erro\w*|quebrou|lento|lentidão)\b`)

// EhCasoDeFalha decide se a pergunta descreve um DEFEITO — que é o que o corpus
// existe para ensinar — ou uma tarefa de configuração.
//
// A regra é assimétrica de propósito: um título de "como faço" só é aceito se o
// corpo descrever falha explícita ("how to fix the BSOD after update" é caso;
// "how to dual boot" não é). Na dúvida, exige-se o sinal de falha — prior
// envenenado é pior que corpus menor.
func EhCasoDeFalha(titulo, corpo string) bool {
	if reFalha.MatchString(titulo) {
		return true
	}
	if reComoFazer.MatchString(strings.TrimSpace(titulo)) {
		return false
	}
	return reFalha.MatchString(corpo)
}

// ClassePorTags mapeia a pergunta para a classe de problema usada no
// coverage_report (§13.6). Cobertura é medida POR CLASSE, nunca em agregado —
// média alta esconde uma classe inteira em zero, e é exatamente isso que este
// campo existe para impedir.
func ClassePorTags(tags, titulo string) string {
	t := strings.ToLower(tags + " " + titulo)
	// Ordem importa: a primeira que casar vence, e as mais específicas vêm
	// primeiro. "ssd travando" é disco, não desempenho.
	classes := []struct {
		classe string
		termos []string
	}{
		{"disco", []string{"hard-drive", "hdd", "ssd", "smart", "disk-failure", "bad sector", "disco"}},
		{"memoria", []string{"memory", "ram", "memtest", "memória"}},
		{"termico", []string{"overheating", "temperature", "fan", "thermal", "superaquec"}},
		{"energia", []string{"power-supply", "battery", "psu", "shutdown", "não liga", "nao liga"}},
		{"driver", []string{"driver", "device-manager", "code 43"}},
		{"software", []string{"windows-update", "software", "application", "malware", "virus"}},
		{"rede", []string{"network", "wifi", "ethernet", "internet", "rede"}},
		// Sintomas sem peça nomeada. Vêm por último de propósito: se a pergunta
		// disser "ssd travando", ela já saiu como disco lá em cima. O que sobra
		// aqui é o caso em que o sintoma é tudo o que se sabe — e esse é
		// justamente o material do status negativo (§1), não lixo.
		{"trava", []string{"freeze", "hang", "crash", "not responding", "lock up", "lockup",
			"bsod", "blue-screen-of-death", "kernel-panic", "system-crash", "trava"}},
		{"boot", []string{"boot", "startup", "post", "não inicia", "nao inicia", "won't start"}},
		{"desempenho", []string{"performance", "slow", "lag", "lentidão", "lentidao"}},
	}
	for _, c := range classes {
		if contemTermo(t, c.termos) {
			return c.classe
		}
	}
	return "indefinido"
}
