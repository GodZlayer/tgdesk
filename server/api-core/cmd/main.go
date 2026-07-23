package main

import (
	"context"
	"log"
	"net/http"
	"strconv"

	"github.com/redis/go-redis/v9"

	"tgdesk/api-core/internal/config"
	"tgdesk/api-core/internal/db"
	"tgdesk/api-core/internal/handlers"
	"tgdesk/api-core/internal/seed"
	"tgdesk/api-core/internal/wg"
)

func main() {
	ctx := context.Background()
	cfg := config.Load()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("postgres: %v", err)
	}
	defer pool.Close()

	if err := db.RunMigrations(ctx, pool, "migrations"); err != nil {
		log.Fatalf("migrations: %v", err)
	}
	log.Println("migrations aplicadas")

	rdb := redis.NewClient(&redis.Options{Addr: cfg.RedisAddr})
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatalf("redis: %v", err)
	}

	if err := seed.Run(ctx, pool, cfg); err != nil {
		log.Fatalf("seed: %v", err)
	}
	log.Println("seed concluído")

	var hub *wg.Hub
	port, perr := strconv.Atoi(cfg.HubListenPort)
	if perr != nil {
		log.Printf("wg-orchestrator: HUB_LISTEN_PORT inválido (%v), hub desabilitado", perr)
	} else if h, err := wg.StartHub(cfg.HubKeyFile, port, cfg.HubCIDR); err != nil {
		log.Printf("wg-orchestrator: hub desabilitado (%v) — dispositivos poderão se vincular, mas sem túnel real", err)
	} else {
		hub = h
		log.Printf("wg-orchestrator: hub ativo, pubkey=%s porta=%d cidr=%s", hub.PublicKey.Base64(), port, cfg.HubCIDR)
	}

	s := &handlers.Server{Pool: pool, RDB: rdb, Cfg: cfg, Hub: hub}
	router := handlers.NewRouter(s)

	log.Printf("api-core ouvindo em %s", cfg.ListenAddr)
	if err := http.ListenAndServe(cfg.ListenAddr, router); err != nil {
		log.Fatalf("http server: %v", err)
	}
}
