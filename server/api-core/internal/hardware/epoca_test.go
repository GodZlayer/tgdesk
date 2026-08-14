package hardware

import "testing"

const inventarioBase = `{
  "cpu": {"name": "AMD Ryzen 5 8500G", "usage": 16, "clock_mhz": 4013},
  "memory": [
    {"slot": "DIMM 0", "type": "DDR5", "part_number": "CMK32GX5M1B5200C40", "total_bytes": 34359738368}
  ],
  "storage": [
    {"model": "KINGSTON SNV3S1000G", "total_bytes": 1000204886016, "bus_type": "NVMe", "used_pct": 97.7, "temperature": 39}
  ],
  "gpus": [{"name": "NVIDIA GeForce GTX 1660", "usage": 33, "temperature": 41}]
}`

// A identidade da máquina não pode mudar porque o usuário usou a máquina.
//
// Se ocupação, temperatura ou clock entrassem na impressão, salvar um arquivo
// ou o processador esquentar seria registrado como troca de peça — e toda
// medição anterior seria descartada por engano.
func TestEstadoNaoAlteraAIdentidade(t *testing.T) {
	primeiro, err := Retratar([]byte(inventarioBase))
	if err != nil {
		t.Fatalf("retratar: %v", err)
	}
	usado := `{
	  "cpu": {"name": "AMD Ryzen 5 8500G", "usage": 91, "clock_mhz": 3200},
	  "memory": [
	    {"slot": "DIMM 0", "type": "DDR5", "part_number": "CMK32GX5M1B5200C40", "total_bytes": 34359738368}
	  ],
	  "storage": [
	    {"model": "KINGSTON SNV3S1000G", "total_bytes": 1000204886016, "bus_type": "NVMe", "used_pct": 41.2, "temperature": 55}
	  ],
	  "gpus": [{"name": "NVIDIA GeForce GTX 1660", "usage": 99, "temperature": 78}]
	}`
	segundo, err := Retratar([]byte(usado))
	if err != nil {
		t.Fatalf("retratar: %v", err)
	}
	if primeiro.Impressao != segundo.Impressao {
		t.Errorf("uso mudou a identidade da máquina: %s → %s",
			primeiro.Impressao, segundo.Impressao)
	}
}

// Somar um pente é a alteração mais comum do parque, e precisa ser vista —
// inclusive porque ela muda o desempenho esperado da máquina.
func TestSomarModuloDeMemoriaEDetectado(t *testing.T) {
	antes, _ := Retratar([]byte(inventarioBase))
	comDois := `{
	  "cpu": {"name": "AMD Ryzen 5 8500G"},
	  "memory": [
	    {"slot": "DIMM 0", "type": "DDR5", "part_number": "CMK32GX5M1B5200C40", "total_bytes": 34359738368},
	    {"slot": "DIMM 1", "type": "DDR5", "part_number": "CMK32GX5M1B5200C40", "total_bytes": 34359738368}
	  ],
	  "storage": [{"model": "KINGSTON SNV3S1000G", "total_bytes": 1000204886016, "bus_type": "NVMe"}],
	  "gpus": [{"name": "NVIDIA GeForce GTX 1660"}]
	}`
	depois, _ := Retratar([]byte(comDois))
	if antes.Impressao == depois.Impressao {
		t.Fatal("somar um módulo de memória não alterou a impressão")
	}
	mudancas := Comparar(antes, depois)
	if len(mudancas) != 1 || mudancas[0].Tipo != "adicionada" || mudancas[0].Classe != "memoria" {
		t.Fatalf("esperava uma adição de memória, veio %+v", mudancas)
	}
}

// Trocar o disco precisa aparecer como TROCA, não como uma remoção e uma
// adição soltas: é a troca que explica por que as medidas antigas não valem.
func TestTrocarDiscoApareceComoTroca(t *testing.T) {
	antes, _ := Retratar([]byte(inventarioBase))
	outro := `{
	  "cpu": {"name": "AMD Ryzen 5 8500G"},
	  "memory": [{"slot": "DIMM 0", "type": "DDR5", "part_number": "CMK32GX5M1B5200C40", "total_bytes": 34359738368}],
	  "storage": [{"model": "SAMSUNG 990 PRO", "total_bytes": 2000398934016, "bus_type": "NVMe"}],
	  "gpus": [{"name": "NVIDIA GeForce GTX 1660"}]
	}`
	depois, _ := Retratar([]byte(outro))
	mudancas := Comparar(antes, depois)
	if len(mudancas) != 1 {
		t.Fatalf("esperava uma alteração, veio %+v", mudancas)
	}
	if mudancas[0].Tipo != "trocada" || mudancas[0].Classe != "disco" {
		t.Fatalf("esperava troca de disco, veio %+v", mudancas[0])
	}
	if mudancas[0].Antes == "" || mudancas[0].Depois == "" {
		t.Error("a troca precisa dizer o que saiu e o que entrou")
	}
}

// A ordem em que o coletor lista as peças não pode alterar a identidade.
func TestOrdemDoColetorNaoAlteraAImpressao(t *testing.T) {
	a, _ := Retratar([]byte(inventarioBase))
	invertido := `{
	  "gpus": [{"name": "NVIDIA GeForce GTX 1660"}],
	  "storage": [{"model": "KINGSTON SNV3S1000G", "total_bytes": 1000204886016, "bus_type": "NVMe"}],
	  "memory": [{"slot": "DIMM 0", "type": "DDR5", "part_number": "CMK32GX5M1B5200C40", "total_bytes": 34359738368}],
	  "cpu": {"name": "amd  ryzen 5   8500g"}
	}`
	b, err := Retratar([]byte(invertido))
	if err != nil {
		t.Fatalf("retratar: %v", err)
	}
	if a.Impressao != b.Impressao {
		t.Error("ordem das chaves ou espaçamento do modelo alteraram a impressão")
	}
}

// Mover um pente de slot muda o desempenho da máquina sem trocar peça alguma —
// é canal único virando canal duplo. Precisa ser registrado.
func TestMudarDeSlotEDetectado(t *testing.T) {
	antes, _ := Retratar([]byte(inventarioBase))
	outroSlot := `{
	  "cpu": {"name": "AMD Ryzen 5 8500G"},
	  "memory": [{"slot": "DIMM 1", "type": "DDR5", "part_number": "CMK32GX5M1B5200C40", "total_bytes": 34359738368}],
	  "storage": [{"model": "KINGSTON SNV3S1000G", "total_bytes": 1000204886016, "bus_type": "NVMe"}],
	  "gpus": [{"name": "NVIDIA GeForce GTX 1660"}]
	}`
	depois, _ := Retratar([]byte(outroSlot))
	if antes.Impressao == depois.Impressao {
		t.Error("mudar o módulo de slot não foi detectado, e isso muda a banda de memória")
	}
}
