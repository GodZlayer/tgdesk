package main

import (
	"encoding/json"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// A tela e o agente são o mesmo TGDesk na mesma máquina, não dois clientes do
// servidor. Existe UM canal com o servidor — o do dispositivo — e a tela o
// alcança por aqui.
//
// Sem esta ponte a tela não teria como falar pelo canal, e acabaria mandando
// requisições HTTP por fora: metade do fluxo do cliente entrando por WebSocket
// e metade saindo por HTTP, que é exatamente o desvio que isto corrige.
type uiBridge struct {
	mu       sync.Mutex
	clients  map[*websocket.Conn]struct{}
	outbound chan json.RawMessage
	upgrader websocket.Upgrader
}

func newUIBridge() *uiBridge {
	return &uiBridge{
		clients:  map[*websocket.Conn]struct{}{},
		outbound: make(chan json.RawMessage, 16),
		upgrader: websocket.Upgrader{
			CheckOrigin: func(*http.Request) bool { return true },
		},
	}
}

// Listen sobe o ponto de encontro local. Só aceita conexões vindas da própria
// máquina: quem está fora fala com o servidor pelo canal do dispositivo, nunca
// por aqui.
func (b *uiBridge) Listen(port int) error {
	listener, err := net.Listen("tcp", "127.0.0.1:"+itoa(port))
	if err != nil {
		return err
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/ui", b.handle)
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() { _ = server.Serve(listener) }()
	return nil
}

func (b *uiBridge) handle(w http.ResponseWriter, r *http.Request) {
	conn, err := b.upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	b.mu.Lock()
	b.clients[conn] = struct{}{}
	b.mu.Unlock()
	defer func() {
		b.mu.Lock()
		delete(b.clients, conn)
		b.mu.Unlock()
		_ = conn.Close()
	}()
	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			return
		}
		// Encaminha ao servidor pelo canal do dispositivo. A ponte não decide
		// nada: quem autoriza é o servidor, pela credencial do canal.
		select {
		case b.outbound <- json.RawMessage(data):
		default:
		}
	}
}

// Broadcast entrega às telas abertas o que chegou do servidor.
func (b *uiBridge) Broadcast(payload any) {
	data, err := json.Marshal(payload)
	if err != nil {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	for conn := range b.clients {
		_ = conn.WriteMessage(websocket.TextMessage, data)
	}
}

func itoa(v int) string {
	if v == 0 {
		return "0"
	}
	digits := ""
	for v > 0 {
		digits = string(rune('0'+v%10)) + digits
		v /= 10
	}
	return digits
}
