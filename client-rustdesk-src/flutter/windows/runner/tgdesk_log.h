#ifndef RUNNER_TGDESK_LOG_H_
#define RUNNER_TGDESK_LOG_H_

#include <string>

// Log de diagnóstico do runner, desligado por padrão.
//
// Existe porque defeitos de geometria de janela — faixa preta, conteúdo
// deslocado, view fora do tamanho — só se explicam vendo a sequência de
// mensagens do Windows com os retângulos de cada uma. Deduzir pelo código já
// custou correções que sequer executavam.
//
// Liga de duas formas, escolhidas para não exigir recompilar nem editar o
// registro:
//
//   - variável de ambiente TGDESK_DEBUG_LOG=1, ou
//   - arquivo C:\ProgramData\TGDesk\logs\debug.on (basta existir, pode estar
//     vazio) — este é o caminho para ligar numa máquina de cliente.
//
// A decisão é lida UMA vez, na primeira chamada: um teste de arquivo por
// mensagem de janela custaria caro justamente durante um redimensionamento.
bool TgdeskLogEnabled();

// Escreve uma linha em C:\ProgramData\TGDesk\logs\tgdesk-diag.log.
//
// `area` identifica o assunto ("wnd", "canvas", ...) para dar para filtrar o
// arquivo depois. Não faz nada quando o log está desligado, e o custo nesse
// caso é um teste de booleano.
void TgdeskLog(const char* area, const std::string& message);

#endif  // RUNNER_TGDESK_LOG_H_
