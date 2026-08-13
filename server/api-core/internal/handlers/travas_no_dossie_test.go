package handlers

import "testing"

// A regra que custou 2.275 eventos falsos para ser aprendida: `indeterminado`
// NÃO é trava. É buraco de heartbeat que o agente não confirmou — quase sempre
// queda de rede. Contar isso como congelamento é dizer ao cliente que o
// computador dele trava toda vez que o Wi-Fi oscila.
//
// O teste olha a consulta porque é ali que o filtro vive. Um teste de
// comportamento precisaria de banco; este pega a regressão que importa, que é
// alguém afrouxar o filtro para "ter mais dado".
func TestSoTravaConfirmadaEntraNoDiagnostico(t *testing.T) {
	fonte := lerFonte(t, "travas_no_dossie.go")

	if !contemTodos(fonte, []string{
		"origem = 'trava'",
		"count(*) FILTER (WHERE origem = 'trava')",
	}) {
		t.Error("o perfil de travas precisa contar SÓ origem='trava'")
	}

	// O contador de indeterminados existe, mas para reportar qualidade de
	// canal — nunca para virar status. Se ele aparecer decidindo status, é
	// regressão.
	if contemTodos(fonte, []string{"p.Indeterminadas >= "}) {
		t.Error("indeterminado está decidindo status: buraco de rede viraria travamento")
	}
}

// Congelamento breve e repetido é fenômeno diferente de trava longa: um é
// disputa que volta sozinha, outro é esgotamento ou peça falhando. Condutas
// diferentes exigem status diferentes — é a regra que funda a taxonomia.
func TestCongelamentoBreveTemStatusProprio(t *testing.T) {
	fonte := lerFonte(t, "travas_no_dossie.go")
	if !contemTodos(fonte, []string{"congelamento_breve_repetido", "trava_sob_carga"}) {
		t.Error("congelamento breve e trava longa precisam de status distintos")
	}
}
