package main

import "math/rand"

// embaralharPosicoes randomiza a ordem de visita de uma varredura.
//
// Sem isso, tempo e espaço andam juntos numa varredura sequencial: se a
// máquina fica ocupada durante um trecho do exame, a lentidão daquele MOMENTO
// aparece no relatório como se fosse uma REGIÃO ruim do disco.
//
// Não é hipótese. Numa varredura do parque isso produziu um miolo a 59-88 MB/s
// contra bordas a 177-216 MB/s, com leituras de até 37 segundos — um padrão
// limpo, convincente e falso. Repetida, a zona não reapareceu. E o próprio
// exame, que chega a 177 MB/s de leitura, é candidato a ter causado a carga.
//
// Embaralhada a ordem, um período ruim espalha pontos por todo o disco em vez
// de agrupá-los. Zona ruim de verdade continua agrupada — porque ela pertence
// ao disco, não ao relógio. É isso que torna o resultado interpretável.
//
// Fisher-Yates com a fonte global: aqui não se quer imprevisibilidade
// criptográfica, se quer ausência de correlação com o tempo.
func embaralharPosicoes(p []uint64) {
	rand.Shuffle(len(p), func(i, j int) { p[i], p[j] = p[j], p[i] })
}
