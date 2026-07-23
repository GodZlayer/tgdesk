package config

import "os"

type Config struct {
	DatabaseURL   string
	RedisAddr     string
	JWTSecret     string
	ListenAddr    string
	TechUsers     string
	TechAssign    string
	SeedOrgs      string
	ForceReseed   bool
	HubListenPort string
	HubCIDR       string
	HubKeyFile    string
	HubPublicAddr string // host:port que os clientes devem discar (endpoint público/local do hub)

	RendezvousKeyFile string // id_ed25519.pub do hbbs, montado read-only
	RendezvousHost    string // host (sem porta) que os clientes devem usar como custom-rendezvous-server
}

func Load() Config {
	return Config{
		DatabaseURL:   mustEnv("DATABASE_URL", "postgres://tgdesk:tgdesk@postgres:5432/tgdesk?sslmode=disable"),
		RedisAddr:     mustEnv("REDIS_ADDR", "redis:6379"),
		JWTSecret:     mustEnv("JWT_SECRET", "change-me-in-production"),
		ListenAddr:    mustEnv("LISTEN_ADDR", ":8080"),
		TechUsers:     os.Getenv("TECH_USERS"),
		TechAssign:    os.Getenv("TECH_ASSIGN"),
		SeedOrgs:      os.Getenv("SEED_ORGANIZATIONS"),
		ForceReseed:   os.Getenv("FORCE_RESEED") == "true",
		HubListenPort: mustEnv("HUB_LISTEN_PORT", "51820"),
		HubCIDR:       mustEnv("HUB_CIDR", "10.70.0.1/16"),
		HubKeyFile:    mustEnv("HUB_KEY_FILE", "/data/hub_private_key"),
		HubPublicAddr: mustEnv("HUB_PUBLIC_ADDR", "127.0.0.1:51820"),

		RendezvousKeyFile: mustEnv("RENDEZVOUS_KEY_FILE", "/hbbs-data/id_ed25519.pub"),
		RendezvousHost:    mustEnv("RENDEZVOUS_PUBLIC_HOST", "127.0.0.1"),
	}
}

func mustEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
