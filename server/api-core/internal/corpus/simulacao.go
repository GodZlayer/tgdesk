package corpus

import "sort"

// Simulação: caso real vira dossiê sintético (§19.3 da arquitetura).
//
// O caso real tem entrada (as medidas do log) e saída (a causa que os humanos
// confirmaram). Falta a FORMA: pôr as medidas nos campos que o dossiê do TGDesk
// usa, para que o mesmo motor que atende um cliente possa ser exercitado contra
// um caso de fórum.
//
// A regra de §19.3, que este arquivo não pode violar em nenhuma linha:
//
//	o que se sintetiza é o FORMATO, nunca o número.
//
// Onde o caso não disser o valor, o campo fica ausente. Não existe valor padrão,
// não existe zero de preenchimento, não existe média. Um dossiê sintético com
// campo inventado deixaria de ser evidência e viraria opinião nossa com aparência
// de dado — e a rede aprenderia a nossa opinião.

// EvidenciaSintetica é uma medida já traduzida para o formato que o motor lê.
type EvidenciaSintetica struct {
	// Sinal do vocabulário de §13.6, que é o que o motor casa contra as causas.
	Sinal string `json:"sinal"`
	// A linha do log, literal. Continua sendo a evidência citável.
	Literal string `json:"literal"`
	// Nulo quando a medida é categórica. Nulo ≠ zero.
	Valor *float64 `json:"valor,omitempty"`
}

// DossieSintetico é um exemplo de treino pronto.
type DossieSintetico struct {
	// Origem, sempre. Um exemplo que não diz de onde veio não pode ser
	// auditado nem removido do conjunto se a extração se mostrar errada.
	ThreadID string `json:"thread_id"`
	Sintoma  string `json:"sintoma"`

	Evidencias []EvidenciaSintetica `json:"evidencias"`

	// O rótulo: o desfecho a que o grupo de humanos chegou. É o alvo do treino.
	Rotulo string `json:"rotulo"`

	// SEMPRE verdadeiro aqui, e é coluna própria de propósito (§19.3): nenhuma
	// métrica de calibração pode ser calculada com estes exemplos. Simulação
	// treina; realidade promove.
	Simulado bool `json:"simulado"`

	// Sem curva: o caso de fórum não tem escada, não tem degrau, não tem
	// limiar. O motor precisa saber disso para aplicar o teto de §10.5.1 — um
	// exemplo de fórum nunca deveria produzir veredito, só hipótese.
	TemCurva bool `json:"tem_curva"`
}

// medidaParaSinal traduz o campo/chave da medida para o vocabulário de sinais.
//
// A tradução é explícita, item a item, e não por regra genérica: cada linha
// aqui é uma afirmação de que aquela medida É aquele sinal, e afirmação
// implícita é a que ninguém revisa.
func medidaParaSinal(m Medida) string {
	switch m.Campo {
	case "smart":
		switch m.Chave {
		case "reallocated":
			return "smart_reallocated"
		case "pending":
			return "smart_pending"
		case "uncorrectable", "crc":
			return "erro_io_log"
		case "horas_ligado", "desgaste":
			// Desgaste e horas ligadas dizem IDADE, não falha. Mapeá-los para
			// um sinal de defeito ensinaria a rede que disco velho é disco
			// quebrado — que é justamente o erro que o técnico já comete.
			return "smart_geral"
		}
		return "smart_geral"
	case "bugcheck":
		return "bugcheck"
	case "temperatura":
		return "temperatura"
	case "evento_sistema":
		// O nível declarado pelo próprio sistema separa erro de informativo.
		// Evento informativo não é evidência de falha (§7.3).
		if m.Nivel == "Error" || m.Nivel == "Critical" {
			return "erro_sistema_log"
		}
		return ""
	case "kernel_panic":
		return "bugcheck"
	case "boot_loader":
		return "boot_falho"
	}
	return ""
}

// Sintetizar transforma um caso real em exemplo de treino.
//
// Devolve `ok=false` quando o caso não rende evidência traduzível — e isso é
// resposta legítima. Forçar todo caso a virar exemplo encheria o conjunto de
// treino com linhas vazias rotuladas, que é a forma mais eficiente de ensinar
// uma rede a chutar.
func Sintetizar(c CasoReal) (DossieSintetico, bool) {
	vistos := map[string]bool{}
	var evidencias []EvidenciaSintetica

	for _, m := range c.Medidas {
		sinal := medidaParaSinal(m)
		if sinal == "" || vistos[sinal] {
			continue
		}
		vistos[sinal] = true
		evidencias = append(evidencias, EvidenciaSintetica{
			Sinal:   sinal,
			Literal: m.Literal,
			// Copiado, nunca preenchido: se a medida não tinha valor, a
			// evidência também não tem.
			Valor: m.Valor,
		})
	}

	if len(evidencias) == 0 || c.Classe == "" || c.Classe == "indefinido" {
		// Sem evidência traduzível, ou sem rótulo utilizável, não há exemplo.
		return DossieSintetico{}, false
	}

	sort.Slice(evidencias, func(a, b int) bool {
		return evidencias[a].Sinal < evidencias[b].Sinal
	})

	return DossieSintetico{
		ThreadID:   c.ThreadID,
		Sintoma:    c.Sintoma,
		Evidencias: evidencias,
		Rotulo:     c.Classe,
		Simulado:   true,
		TemCurva:   false,
	}, true
}

// ConjuntoDeTreino agrega os exemplos e diz o que há neles.
type ConjuntoDeTreino struct {
	Exemplos   []DossieSintetico
	PorRotulo  map[string]int
	PorSinal   map[string]int
	SemExemplo int
}

// Montar constrói o conjunto a partir dos casos reais.
func Montar(casos []CasoReal) ConjuntoDeTreino {
	c := ConjuntoDeTreino{
		PorRotulo: map[string]int{},
		PorSinal:  map[string]int{},
	}
	for _, caso := range casos {
		d, ok := Sintetizar(caso)
		if !ok {
			c.SemExemplo++
			continue
		}
		c.Exemplos = append(c.Exemplos, d)
		c.PorRotulo[d.Rotulo]++
		for _, e := range d.Evidencias {
			c.PorSinal[e.Sinal]++
		}
	}
	return c
}

// RotulosComVolumeMinimo devolve os rótulos que têm exemplos suficientes para
// treinar alguma coisa.
//
// Existe porque treinar uma classe com 2 exemplos não produz modelo: produz
// memorização com aparência de aprendizado. O piso é explícito e revisável em
// vez de embutido no treino.
func (c ConjuntoDeTreino) RotulosComVolumeMinimo(minimo int) []string {
	var saida []string
	for r, n := range c.PorRotulo {
		if n >= minimo {
			saida = append(saida, r)
		}
	}
	sort.Strings(saida)
	return saida
}
