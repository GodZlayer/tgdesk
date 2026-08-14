package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"time"

	"github.com/gorilla/websocket"

	"tgdesk/agent/internal/updatecore"
)

type deviceControlMessage struct {
	Type    string `json:"type"`
	ID      string `json:"id,omitempty"`
	State   string `json:"state,omitempty"`
	Version string `json:"version,omitempty"`
	Payload any    `json:"payload,omitempty"`
}

// deteccaoDeRegistroConfiavel diz se a evidência disponível sustenta declarar o
// registro instável e agir sobre isso.
//
// Hoje é false: a única fonte é a tabela TCP, e ela mede sondas de latência, não
// registro. Volta a true quando o sinal vier de quem sabe — o rendezvous.
const deteccaoDeRegistroConfiavel = false

func privateControlURL(cfg *agentConfig) string {
	q := url.Values{}
	q.Set("device_id", cfg.DeviceID)
	q.Set("device_token", cfg.DeviceToken)
	return "ws://10.70.0.1:8080/ws/control/device?" + q.Encode()
}

// runDeviceControlLoop substitui heartbeat e telemetria HTTP depois que a
// VPN está disponível. O retorno sempre significa que o canal privado caiu.
// uiChannel é a ponte com as telas desta máquina. Vive fora do laço porque o
// canal com o servidor pode cair e reconectar, e a tela não deve perceber.
var uiChannel = newUIBridge()

// UIBridgePort é a porta local onde a tela encontra o agente.
const UIBridgePort = 47615

func runDeviceControlLoop(cfg *agentConfig, remoteReady bool) error {
	_ = uiChannel.Listen(UIBridgePort)
	conn, _, err := websocket.DefaultDialer.Dial(privateControlURL(cfg), nil)
	if err != nil {
		return fmt.Errorf("conectar controle privado: %w", err)
	}
	defer conn.Close()

	readErr := make(chan error, 1)
	statsCh := make(chan any, 1)
	brandingCh := make(chan BrandingState, 1)
	diagnosticCh := make(chan diagnosticRequest, 1)
	diagnosticCancelCh := make(chan string, 1)
	diagnosticPauseCh := make(chan struct {
		ID     string
		Paused bool
	}, 2)
	diagnosticProgressCh := make(chan diagnosticProgress, 8)
	diagnosticResultCh := make(chan diagnosticResult, 1)
	updateOrderCh := make(chan updateOrder, 1)
	updateProgressCh := make(chan updatecore.Progress, 8)
	updateResultCh := make(chan updateOutcome, 1)
	go func() {
		for {
			var msg deviceControlMessage
			if err := conn.ReadJSON(&msg); err != nil {
				readErr <- err
				return
			}
			// Respostas de RPC e eventos do chamado seguem para a tela pela
			// ponte local: um canal só com o servidor, várias telas possíveis.
			if msg.Type == "rpc_response" || msg.Type == "ticket_thread" {
				uiChannel.Broadcast(msg)
			}
			if msg.Type == "heartbeat_ack" {
				uiChannel.Broadcast(msg)
			}
			if msg.Type == "telemetry_stats" {
				select {
				case statsCh <- msg.Payload:
				default:
				}
			}
			if msg.Type == "ready" || msg.Type == "branding" {
				raw, _ := json.Marshal(msg.Payload)
				var branding BrandingState
				if msg.Type == "ready" {
					var payload struct {
						Branding BrandingState `json:"branding"`
					}
					if json.Unmarshal(raw, &payload) == nil {
						branding = payload.Branding
					}
				} else {
					_ = json.Unmarshal(raw, &branding)
				}
				if branding.Name == "" {
					branding.Name = "TGDesk"
				}
				syncBrandFavicon(branding)
				select {
				case brandingCh <- branding:
				default:
				}
			}
			if msg.Type == "diagnostic_run" && msg.ID != "" {
				raw, _ := json.Marshal(msg.Payload)
				var payload struct {
					Test  string   `json:"test"`
					Tests []string `json:"tests"`
				}
				if json.Unmarshal(raw, &payload) == nil {
					if len(payload.Tests) == 0 && payload.Test != "" {
						payload.Tests = []string{payload.Test}
					}
					if len(payload.Tests) == 0 {
						continue
					}
					select {
					case diagnosticCh <- diagnosticRequest{ID: msg.ID, Tests: payload.Tests}:
					default:
					}
				}
			}
			if msg.Type == "diagnostic_cancel" && msg.ID != "" {
				select {
				case diagnosticCancelCh <- msg.ID:
				default:
				}
			}
			if msg.Type == "diagnostic_pause" && msg.ID != "" {
				paused := true
				if payload, ok := msg.Payload.(map[string]any); ok {
					if value, exists := payload["paused"].(bool); exists {
						paused = value
					}
				}
				select {
				case diagnosticPauseCh <- struct {
					ID     string
					Paused bool
				}{msg.ID, paused}:
				default:
				}
			}
			if msg.Type == "update_now" {
				raw, _ := json.Marshal(msg.Payload)
				var order updateOrder
				if json.Unmarshal(raw, &order) == nil && order.Version != "" {
					uiChannel.Broadcast(map[string]any{
						"type": "update_status",
						"payload": map[string]any{
							"updating": true,
							"update_progress": map[string]any{
								"version":       order.Version,
								"throttle_kbps": order.ThrottleKbps,
							},
						},
					})
					select {
					case updateOrderCh <- order:
					default:
					}
				}
			}
			if msg.Version != "" {
				setServerUpdateVersion(msg.Version)
			}
			if msg.State == "suspenso" {
				readErr <- fmt.Errorf("dispositivo suspenso")
				return
			}
		}
	}()

	heartbeatTick := time.NewTicker(5 * time.Second)
	telemetryTick := time.NewTicker(30 * time.Second)
	remoteRetryTick := time.NewTicker(15 * time.Second)
	// Batida de alta frequência (2 Hz, §6). É separada do heartbeat de 5s de
	// propósito: aquele carrega estado, versão e capacidades, e escreve no
	// banco do servidor. Este é só um pulso — o que interessa dele é o BURACO
	// quando ele para de chegar.
	pulseTick := time.NewTicker(500 * time.Millisecond)
	defer pulseTick.Stop()
	// Vive no processo, não na conexão: a trava costuma derrubar o canal, e um
	// buffer que morresse junto perderia o contexto do evento.
	ringTrava := ringBufferDeTrava()
	// Autoteste do canal de contexto de trava, uma vez por conexão.
	//
	// A transmissão do `stall_context` só acontece depois de um congelamento —
	// então, sem isto, o caminho crítico do detector ficaria sem prova até o dia
	// em que precisa funcionar. Exercitá-lo na conexão custa uma mensagem e
	// transforma "deve funcionar" em "funcionou às 07:52".
	autotesteCanal := time.NewTimer(8 * time.Second)
	defer autotesteCanal.Stop()
	// Até quando o reparo do acesso remoto fica em carência. Reconfigurar é
	// aposta, e aposta precisa de tempo para se provar antes de virar promessa.
	var carenciaAte time.Time
	// Canal com folga de 1: a coleta entrega e segue, sem esperar o laço.
	telemetriaPronta := make(chan HardwareSnapshot, 1)
	coletando := false

	// Telemetria local: coleta barata e frequente, entrega oportunista.
	//
	// A coleta NÃO depende do canal — é isso que faz a máquina sem internet
	// continuar medindo, e é ela que costuma estar com problema. O dreno é que
	// depende, e ele só descarta depois do aceite do servidor.
	spool := novoSpool(tgdeskDataDir())
	defer spool.Fechar()
	coletaBarataTick := time.NewTicker(10 * time.Second)
	defer coletaBarataTick.Stop()
	drenoTick := time.NewTicker(20 * time.Second)
	defer drenoTick.Stop()
	defer heartbeatTick.Stop()
	defer telemetryTick.Stop()
	defer remoteRetryTick.Stop()

	sendHeartbeat := func() error {
		return conn.WriteJSON(deviceControlMessage{
			Type: "heartbeat",
			Payload: map[string]any{
				"remote_ready": remoteReady,
				"files_ready":  remoteReady,
				// A versão que roda de fato vai no heartbeat porque é o
				// servidor quem decide quem atualiza — ele não pergunta.
				"client_version": updatecore.CurrentClientVersion(),
			},
		})
	}
	if err := sendHeartbeat(); err != nil {
		return err
	}
	if cfg.RustdeskID != "" {
		_ = conn.WriteJSON(deviceControlMessage{
			Type:    "rustdesk_status",
			Payload: map[string]string{"rustdesk_id": cfg.RustdeskID},
		})
	}

	var hardware HardwareSnapshot
	var statistics any
	var collectedAt string
	var remoteError string
	branding := BrandingState{Name: "TGDesk"}
	type activeDiagnostic struct {
		cancel context.CancelFunc
		pause  *diagnosticPauseGate
	}
	activeDiagnostics := map[string]activeDiagnostic{}
	writeCurrentStatus := func() {
		writeStatus(tgdeskStatus{
			State: "ativo", Hostname: localHostname(), DeviceID: cfg.DeviceID,
			VirtualIP: cfg.VirtualIP, RustdeskID: cfg.RustdeskID, TunnelUp: true,
			Hardware: hardware, Statistics: statistics, CollectedAt: collectedAt,
			RemoteReady: remoteReady, FilesReady: remoteReady,
			RemoteError: remoteError,
			Branding:    branding,
		})
	}
	for {
		select {
		case err := <-readErr:
			return err
		case fromUI := <-uiChannel.outbound:
			// A tela fala com o servidor por este canal — nunca por fora dele.
			if conn.WriteMessage(websocket.TextMessage, fromUI) != nil {
				return fmt.Errorf("canal privado caiu ao encaminhar a tela")
			}
		case statistics = <-statsCh:
			writeCurrentStatus()
		case branding = <-brandingCh:
			writeCurrentStatus()
		case request := <-diagnosticCh:
			ctx, cancel := context.WithCancel(context.Background())
			gate := newDiagnosticPauseGate()
			activeDiagnostics[request.ID] = activeDiagnostic{cancel: cancel, pause: gate}
			go runDiagnostic(ctx, request, gate, diagnosticProgressCh, diagnosticResultCh)
		case order := <-updateOrderCh:
			startForcedUpdate(order,
				func(progress updatecore.Progress) {
					select {
					case updateProgressCh <- progress:
					default:
					}
				},
				func(outcome updateOutcome) {
					select {
					case updateResultCh <- outcome:
					default:
					}
				})
			uiChannel.Broadcast(map[string]any{
				"type": "update_status",
				"payload": map[string]any{
					"updating": true,
					"update_progress": map[string]any{
						"version":       order.Version,
						"throttle_kbps": order.ThrottleKbps,
					},
				},
			})
			writeCurrentStatus()
		case progress := <-updateProgressCh:
			// O andamento vai para a tela pelo status; o servidor só precisa
			// saber quando terminou, para liberar o próximo da fila.
			writeCurrentStatus()
			uiChannel.Broadcast(map[string]any{
				"type": "update_status",
				"payload": map[string]any{
					"updating":        true,
					"update_progress": progress,
				},
			})
		case outcome := <-updateResultCh:
			writeCurrentStatus()
			uiChannel.Broadcast(map[string]any{
				"type":    "update_status",
				"payload": map[string]any{"updating": false, "outcome": outcome},
			})
			if err := conn.WriteJSON(deviceControlMessage{
				Type: "update_result", Payload: outcome,
			}); err != nil {
				return err
			}
		case id := <-diagnosticCancelCh:
			if active, exists := activeDiagnostics[id]; exists {
				active.cancel()
			}
		case request := <-diagnosticPauseCh:
			if active, exists := activeDiagnostics[request.ID]; exists {
				active.pause.set(request.Paused)
			}
		case progress := <-diagnosticProgressCh:
			if err := conn.WriteJSON(deviceControlMessage{
				Type: "diagnostic_progress", ID: progress.ID, Payload: progress,
			}); err != nil {
				return err
			}
		case result := <-diagnosticResultCh:
			if active, exists := activeDiagnostics[result.ID]; exists {
				active.cancel()
				delete(activeDiagnostics, result.ID)
			}
			if err := conn.WriteJSON(deviceControlMessage{
				Type: "diagnostic_result", ID: result.ID, Payload: result,
			}); err != nil {
				return err
			}
		case <-coletaBarataTick.C:
			// ~100 µs por amostra, só syscall. Roda mesmo sem canal.
			spool.Gravar("amostra", ColetarBarato())

		case <-drenoTick.C:
			// Entrega o que ficou para trás. Um lote por vez: se a conexão
			// cair no meio, o arquivo continua lá e a próxima passagem
			// recomeça dele — reenvio custa banda, perda custa diagnóstico.
			if lote, origem, completo := spool.LotePendente(); len(lote) > 0 {
				if err := conn.WriteJSON(deviceControlMessage{
					Type:    "telemetria_local",
					Payload: map[string]any{"amostras": lote, "completo": completo},
				}); err != nil {
					return err
				}
				spool.ConfirmarEntrega(origem)
			}

		case <-autotesteCanal.C:
			// Marcado como autoteste: o servidor carimba que o canal está de pé
			// e NUNCA cria evento de trava com esta mensagem.
			if err := conn.WriteJSON(deviceControlMessage{
				Type: "stall_context", Payload: ringTrava.contextoDeAutoteste(),
			}); err != nil {
				return err
			}

		case <-pulseTick.C:
			// O pulso não carrega payload: qualquer campo aqui seria custo a
			// 2 Hz sem mudar nada do que o servidor precisa saber.
			if err := conn.WriteJSON(deviceControlMessage{Type: "hb"}); err != nil {
				return err
			}
			// Se o relógio local saltou, houve congelamento — e o contexto do
			// que acontecia em volta sobe DEPOIS do evento, nunca durante.
			// Durante, a máquina estava travada; é essa a razão de o despejo
			// ser posterior.
			if pendente := ringTrava.despejar(); pendente != nil {
				if err := conn.WriteJSON(deviceControlMessage{
					Type: "stall_context", Payload: pendente,
				}); err != nil {
					return err
				}
			}

		case <-heartbeatTick.C:
			if err := sendHeartbeat(); err != nil {
				return err
			}
			writeCurrentStatus()
		case <-remoteRetryTick.C:
			// VERIFICAR, não prometer.
			//
			// `remote_ready` era marcado quando a configuração local dava certo
			// — o que responde "consigo alcançar o servidor?", não "estou
			// registrado?". No parque houve máquina com remote_ready=true,
			// túnel de pé, respondendo a ping, e inacessível: a conexão com o
			// rendezvous trocava de porta a cada 45 s, em ciclo.
			//
			// Agora, enquanto o programa estiver ativo, o acesso remoto é
			// conferido e reparado. É essa a garantia.
			if remoteReady && cfg.RendezvousHost != "" {
				viva, portaLocal, err := ConexaoComPortaLocal(cfg.RendezvousHost, 21116)
				// INSTABILIDADE, não ausência.
				//
				// A primeira versão perguntava "existe conexão agora?" — e
				// existia, a cada instante. Só que era sempre uma conexão NOVA:
				// a porta local ia de 59254 para 58612 entre duas amostras. O
				// ciclo de reconexão passava despercebido por ser rápido demais
				// para deixar buraco.
				//
				// A porta local é a identidade da conexão. Se ela muda, houve
				// reconexão — e reconectar sem parar é o mesmo que não estar
				// registrado, do ponto de vista de quem tenta acessar.
				if err != nil {
					// FALHA DE VERIFICAÇÃO É EVENTO, NÃO SILÊNCIO.
					//
					// A versão anterior só agia quando err == nil, e quando a
					// leitura da tabela TCP falhava o vigia simplesmente parava
					// — sem log, sem estado, sem pista. Foram três releases sem
					// ele disparar e sem eu ter como saber por quê.
					//
					// Um vigia que pode falhar calado não é vigia.
					appendAgentLog("vigia: não consegui verificar o registro: %v", err)
				}
				reconectou := vigiaDoRegistro.viuReconexao(viva, portaLocal)
				if reconectou {
					appendAgentLog("vigia: reconexão com o rendezvous (porta %d)", portaLocal)
				}
				// A TABELA TCP NÃO RESPONDE ESTA PERGUNTA. Premissa derrubada
				// por medição, não por teoria.
				//
				// Este vigia nasceu supondo que o registro no rendezvous é uma
				// conexão TCP persistente, e que troca de porta local significa
				// reconexão. O log do serviço mostrou o contrário: o registro é
				// UDP ("start udp: 10.70.0.1:21116"), e as conexões TCP com a
				// mesma porta são SONDAS DE LATÊNCIA transitórias, cada uma com
				// porta nova por design.
				//
				// Ou seja, `viva` é falso quase sempre e a porta "muda" a cada
				// sonda. O vigia disparava por construção — medido na máquina do
				// Daniel: "registro INSTÁVEL" a cada 2 minutos, ininterrupto,
				// enquanto o log do RustDesk mostrava o mediador iniciado UMA vez
				// e nunca reiniciado.
				//
				// E o dano não era só ruído: a cada disparo ele marcava o acesso
				// remoto como indisponível e reconfigurava o túnel de uma máquina
				// saudável. O vigia que existia para garantir acesso era a causa
				// de perdê-lo, de forma intermitente e aparentemente aleatória.
				//
				// Enquanto não houver um sinal que meça o registro DE VERDADE —
				// e o servidor é quem sabe, porque é o hbbs que registra o peer —
				// a detecção fica em observação: registra no log, não mexe no
				// estado. Prometer menos é melhor que derrubar o que funciona.
				if err == nil && (!viva || reconectou) && deteccaoDeRegistroConfiavel {
					// JANELA, não consecutivos.
					//
					// A versão anterior exigia 3 detecções seguidas e zerava o
					// contador a cada verificação boa. Mas a reconexão acontece
					// a cada ~30-45 s e a verificação a cada 15 s, então a
					// sequência real era: zera, zera, conta 1, zera. O contador
					// nunca chegava a 3.
					//
					// Exigir eventos CONSECUTIVOS de um fenômeno intermitente é
					// errado por construção — e foi por isso que o vigia não
					// disparou numa máquina que reconectava sem parar.
					if vigiaDoRegistro.contar() >= falhasAteReparar {
						// Deixou de estar registrado de forma estável. Dizer a
						// verdade primeiro — a tela precisa parar de prometer
						// acesso que não existe — e só então tentar consertar.
						appendAgentLog("vigia: registro INSTÁVEL — %d reconexões na janela; "+
							"marcando acesso remoto como indisponível e reconfigurando",
							falhasAteReparar)
						remoteReady = false
						remoteError = "registro no rendezvous instável (reconexão em ciclo)"
						vigiaDoRegistro.zerar()
						// CARÊNCIA antes de voltar a prometer.
						//
						// Sem ela, o bloco de reparo logo abaixo rodava no MESMO
						// tick: marcava indisponível, chamava setupRemoteAccess
						// — cujo critério de sucesso é abrir um socket TCP, que
						// sempre funciona — e voltava a dizer remote_ready=true
						// em milissegundos. O estado "instável" nunca chegava a
						// ser visto por ninguém, nem na tela nem no status.
						//
						// Reconfigurar é uma aposta; a aposta precisa de tempo
						// para se provar. Até lá, a verdade é "não está
						// acessível", e é ela que a tela mostra.
						carenciaAte = time.Now().Add(carenciaDeReparo)
						writeCurrentStatus()
						_ = sendHeartbeat()
					}
				}
			}
			if !remoteReady && time.Now().After(carenciaAte) {
				if err := setupRemoteAccess(cfg); err != nil {
					remoteError = err.Error()
				} else {
					remoteReady = true
					remoteError = ""
					if cfg.RustdeskID != "" {
						_ = conn.WriteJSON(deviceControlMessage{
							Type:    "rustdesk_status",
							Payload: map[string]string{"rustdesk_id": cfg.RustdeskID},
						})
					}
					if err := sendHeartbeat(); err != nil {
						return err
					}
				}
				writeCurrentStatus()
			}
		case <-telemetryTick.C:
			// A coleta sai do laço, e isso NÃO é otimização — é correção de um
			// defeito que envenenava o diagnóstico.
			//
			// `collectHardwareSnapshot` roda um script PowerShell com várias
			// consultas CIM e leva de 9 a 13 segundos. Rodando aqui dentro, ela
			// segurava o `select` inteiro — e o pulso de 2 Hz parava junto. O
			// servidor, que mede trava justamente pelo buraco entre pulsos,
			// abria um evento de travamento a cada 30 s, em toda máquina.
			//
			// Eram ~250 travas falsas por máquina por hora, em cima do ÚNICO
			// sinal capaz de detectar congelamento real. O detector de travas
			// estava medindo a própria coleta de telemetria.
			//
			// `coletando` impede acúmulo: se uma coleta demorar mais que o
			// intervalo, a próxima é pulada em vez de empilhar goroutines.
			if !coletando {
				coletando = true
				go func() {
					h := collectHardwareSnapshot()
					select {
					case telemetriaPronta <- h:
					case <-time.After(5 * time.Second):
						// Ninguém para receber: a conexão caiu no meio da
						// coleta. Descartar é certo — o dado seria enviado num
						// canal que não existe mais.
					}
				}()
			}

		case h := <-telemetriaPronta:
			coletando = false
			hardware = h
			collectedAt = time.Now().UTC().Format(time.RFC3339)
			writeCurrentStatus()
			payload, _ := json.Marshal(map[string]any{"hardware": hardware})
			var body any
			_ = json.Unmarshal(payload, &body)
			if err := conn.WriteJSON(deviceControlMessage{Type: "telemetry", Payload: body}); err != nil {
				return err
			}
		}
	}
}
