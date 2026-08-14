// Package hardware identifica DE QUE MÁQUINA uma medida veio.
//
// O diagnóstico começa antes da telemetria: é a peça que define o que medir e
// o que esperar. E existe uma armadilha que só aparece com o tempo — quando
// uma peça é trocada, a máquina passa a ser outra. Comparar medições de antes
// com as de depois é comparar dois computadores e chamar a diferença de
// degradação.
//
// Por isso toda medida pertence a uma ÉPOCA: o intervalo em que a máquina foi
// a mesma máquina.
package hardware

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// Componente é uma peça identificada de forma ESTÁVEL.
//
// Estável quer dizer: sobrevive a reinício, a uso e a temperatura. Modelo,
// capacidade e slot identificam; ocupação, calor e uso descrevem estado e não
// entram aqui — se entrassem, a máquina "mudaria de identidade" toda vez que o
// usuário salvasse um arquivo.
type Componente struct {
	Classe    string `json:"classe"`
	Chave     string `json:"chave"`
	Descricao string `json:"descricao"`
}

// Retrato é o conjunto de peças mais a impressão que as resume.
type Retrato struct {
	Impressao   string       `json:"impressao"`
	Componentes []Componente `json:"componentes"`
}

// Alteracao descreve uma diferença entre dois retratos.
type Alteracao struct {
	Classe string `json:"classe"`
	Tipo   string `json:"tipo"` // adicionada | removida | trocada
	Antes  string `json:"antes,omitempty"`
	Depois string `json:"depois,omitempty"`
}

// Retratar extrai as peças estáveis do inventário coletado pelo agente.
//
// Trabalha sobre o JSON cru de propósito: o formato do inventário muda com o
// tempo, e uma struct rígida faria a identidade da máquina depender da versão
// do agente — uma atualização do cliente apareceria como troca de hardware.
func Retratar(inventario []byte) (Retrato, error) {
	var bruto map[string]json.RawMessage
	if err := json.Unmarshal(inventario, &bruto); err != nil {
		return Retrato{}, fmt.Errorf("inventário inválido: %w", err)
	}

	var pecas []Componente

	// Processador: o nome do modelo. Clock não entra — ele varia com carga.
	if cpu, ok := objeto(bruto["cpu"]); ok {
		if nome := texto(cpu["name"]); nome != "" {
			pecas = append(pecas, Componente{
				Classe: "cpu", Chave: normalizar(nome), Descricao: nome,
			})
		}
	}

	// Memória: cada módulo, pelo slot e pelo que ele é. O SLOT importa —
	// mover um pente de canal muda o desempenho da máquina sem mudar peça
	// nenhuma, e isso precisa aparecer como alteração.
	for _, m := range lista(bruto["memory"]) {
		slot := texto(m["slot"])
		total := numero(m["total_bytes"])
		tipo := texto(m["type"])
		pn := texto(m["part_number"])
		if slot == "" && pn == "" {
			continue
		}
		desc := fmt.Sprintf("%s %s %.0f GB (%s)", tipo, pn, total/(1<<30), slot)
		pecas = append(pecas, Componente{
			Classe:    "memoria",
			Chave:     normalizar(slot + "|" + pn + "|" + fmt.Sprintf("%.0f", total)),
			Descricao: strings.TrimSpace(desc),
		})
	}

	// Discos: modelo e capacidade. Ocupação NÃO entra — encher o disco não
	// troca o disco.
	for _, d := range lista(bruto["storage"]) {
		modelo := texto(d["model"])
		if modelo == "" {
			continue
		}
		total := numero(d["total_bytes"])
		barramento := texto(d["bus_type"])
		desc := fmt.Sprintf("%s %.0f GB %s", modelo, total/(1<<30), barramento)
		pecas = append(pecas, Componente{
			Classe:    "disco",
			Chave:     normalizar(modelo + "|" + fmt.Sprintf("%.0f", total)),
			Descricao: strings.TrimSpace(desc),
		})
	}

	// Vídeo: o nome do controlador.
	for _, g := range lista(bruto["gpus"]) {
		nome := texto(g["name"])
		if nome == "" {
			continue
		}
		pecas = append(pecas, Componente{
			Classe: "gpu", Chave: normalizar(nome), Descricao: nome,
		})
	}

	if len(pecas) == 0 {
		return Retrato{}, fmt.Errorf("nenhuma peça identificável no inventário")
	}

	// Ordem estável: a impressão não pode depender da ordem em que o
	// coletor listou as peças, senão a máquina "muda" a cada coleta.
	sort.Slice(pecas, func(i, j int) bool {
		if pecas[i].Classe != pecas[j].Classe {
			return pecas[i].Classe < pecas[j].Classe
		}
		return pecas[i].Chave < pecas[j].Chave
	})

	soma := sha256.New()
	for _, p := range pecas {
		fmt.Fprintf(soma, "%s:%s\n", p.Classe, p.Chave)
	}
	return Retrato{
		Impressao:   hex.EncodeToString(soma.Sum(nil))[:32],
		Componentes: pecas,
	}, nil
}

// Comparar descreve o que mudou entre dois retratos.
//
// Devolve as alterações em vez de só "mudou": o técnico precisa saber QUE peça
// entrou e qual saiu, e o histórico precisa disso para explicar por que as
// medidas de antes não valem mais.
func Comparar(antes, depois Retrato) []Alteracao {
	anteriores := map[string]Componente{}
	for _, c := range antes.Componentes {
		anteriores[c.Classe+"|"+c.Chave] = c
	}
	atuais := map[string]Componente{}
	for _, c := range depois.Componentes {
		atuais[c.Classe+"|"+c.Chave] = c
	}

	// Por classe, o que saiu e o que entrou. Uma saída com uma entrada na
	// mesma classe é TROCA — dizer "removida" e "adicionada" separadamente
	// esconderia o fato mais informativo do evento.
	saiu := map[string][]Componente{}
	entrou := map[string][]Componente{}
	for k, c := range anteriores {
		if _, existe := atuais[k]; !existe {
			saiu[c.Classe] = append(saiu[c.Classe], c)
		}
	}
	for k, c := range atuais {
		if _, existia := anteriores[k]; !existia {
			entrou[c.Classe] = append(entrou[c.Classe], c)
		}
	}

	var mudancas []Alteracao
	classes := map[string]bool{}
	for c := range saiu {
		classes[c] = true
	}
	for c := range entrou {
		classes[c] = true
	}
	ordenadas := make([]string, 0, len(classes))
	for c := range classes {
		ordenadas = append(ordenadas, c)
	}
	sort.Strings(ordenadas)

	for _, classe := range ordenadas {
		s, e := saiu[classe], entrou[classe]
		sort.Slice(s, func(i, j int) bool { return s[i].Chave < s[j].Chave })
		sort.Slice(e, func(i, j int) bool { return e[i].Chave < e[j].Chave })
		for i := 0; i < len(s) || i < len(e); i++ {
			switch {
			case i < len(s) && i < len(e):
				mudancas = append(mudancas, Alteracao{
					Classe: classe, Tipo: "trocada",
					Antes: s[i].Descricao, Depois: e[i].Descricao,
				})
			case i < len(s):
				mudancas = append(mudancas, Alteracao{
					Classe: classe, Tipo: "removida", Antes: s[i].Descricao,
				})
			default:
				mudancas = append(mudancas, Alteracao{
					Classe: classe, Tipo: "adicionada", Depois: e[i].Descricao,
				})
			}
		}
	}
	return mudancas
}

// --- leitura tolerante do inventário -------------------------------------

func objeto(bruto json.RawMessage) (map[string]any, bool) {
	if len(bruto) == 0 {
		return nil, false
	}
	var m map[string]any
	if json.Unmarshal(bruto, &m) != nil {
		return nil, false
	}
	return m, true
}

func lista(bruto json.RawMessage) []map[string]any {
	if len(bruto) == 0 {
		return nil
	}
	var l []map[string]any
	if json.Unmarshal(bruto, &l) != nil {
		return nil
	}
	return l
}

func texto(v any) string {
	s, _ := v.(string)
	return strings.TrimSpace(s)
}

func numero(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case json.Number:
		f, _ := n.Float64()
		return f
	}
	return 0
}

// normalizar torna a chave insensível a maiúsculas e a espaços repetidos, que
// variam entre versões do coletor sem que a peça tenha mudado.
func normalizar(s string) string {
	return strings.Join(strings.Fields(strings.ToUpper(s)), " ")
}
