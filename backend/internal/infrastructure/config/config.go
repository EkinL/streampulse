package config

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/sethvargo/go-envconfig"
	"github.com/streampulse/backend/internal/infrastructure/observability"
)

type Config struct {
	AppEnv             string        `env:"APP_ENV,default=development"`
	Port               int           `env:"PORT,default=8080"`
	MetricsPort        int           `env:"METRICS_PORT,default=9091"`
	DatabaseURL        string        `env:"DATABASE_URL,required"`
	JWTSecret          string        `env:"JWT_SECRET,required"`
	JWTExpiry          time.Duration `env:"JWT_EXPIRY,default=15m"`
	JWTRefreshExpiry   time.Duration `env:"JWT_REFRESH_EXPIRY,default=168h"`
	OTELEndpoint       string        `env:"OTEL_ENDPOINT,default=localhost:4317"`
	OTELServiceName    string        `env:"OTEL_SERVICE_NAME,default=streampulse-api"`
	LogLevel           string        `env:"LOG_LEVEL,default=info"`
	LogFormat          string        `env:"LOG_FORMAT,default=json"`
	CORSAllowedOrigins string        `env:"CORS_ALLOWED_ORIGINS,default=*"`
	RateLimitRPS       float64       `env:"RATE_LIMIT_RPS,default=10"`
	RateLimitBurst     int           `env:"RATE_LIMIT_BURST,default=20"`
	// Reverse-proxies dont on accepte X-Forwarded-For, en CIDR ou en
	// adresse simple. Vide par defaut : un serveur expose directement ne
	// doit faire confiance a aucun en-tete de transmission.
	TrustedProxies []string `env:"TRUSTED_PROXIES"`

	// Timeouts du serveur HTTP principal. Ils s'appliquent a toutes les routes
	// sauf les connexions longues (SSE, audio, broadcast) qui les levent
	// elles-memes, voir docs/ADR/005-http-timeouts.md.
	HTTPReadTimeout  time.Duration `env:"HTTP_READ_TIMEOUT,default=30s"`
	HTTPWriteTimeout time.Duration `env:"HTTP_WRITE_TIMEOUT,default=30s"`
	HTTPIdleTimeout  time.Duration `env:"HTTP_IDLE_TIMEOUT,default=60s"`

	// TLS natif du serveur HTTP principal. Les deux fichiers renseignes
	// activent HTTPS (TLS 1.2 minimum). Vides, le serveur reste en clair :
	// c'est le cas derriere un reverse proxy qui termine TLS, voir
	// docs/deployment.md. Le listener interne METRICS_PORT n'est jamais
	// chiffre, il ne sort pas du reseau Docker.
	TLSCertFile string `env:"TLS_CERT_FILE"`
	TLSKeyFile  string `env:"TLS_KEY_FILE"`

	// URL publique de l'API, telle que les clients la joignent : sert a
	// construire les URL des fichiers uploades. Vide, elle est deduite du
	// port et de l'activation de TLS (http(s)://localhost:PORT), ce qui
	// convient au simulateur et a la stack locale.
	PublicBaseURLOverride string `env:"PUBLIC_BASE_URL"`

	// Intervalle de purge des refresh tokens expires. Politique de retention
	// (docs/rgpd.md) : un jeton expire ne sert plus a rien, on ne le garde pas.
	RefreshTokenPurgeInterval time.Duration `env:"REFRESH_TOKEN_PURGE_INTERVAL,default=1h"`
}

func Load() (*Config, error) {
	var cfg Config
	if err := envconfig.Process(context.Background(), &cfg); err != nil {
		return nil, fmt.Errorf("config: load: %w", err)
	}
	// On echoue au demarrage plutot que de retomber silencieusement sur un
	// defaut : une faute de frappe dans LOG_FORMAT donnerait des logs non
	// indexables en production sans que personne ne le remarque.
	if !observability.IsValidLogFormat(cfg.LogFormat) {
		return nil, fmt.Errorf("config: load: %w", observability.FormatError(cfg.LogFormat))
	}
	// Un seul des deux fichiers TLS, c'est forcement une erreur de
	// deploiement : mieux vaut refuser de demarrer que servir en clair en
	// croyant servir en HTTPS.
	if (cfg.TLSCertFile == "") != (cfg.TLSKeyFile == "") {
		return nil, fmt.Errorf("config: load: TLS_CERT_FILE and TLS_KEY_FILE must be set together")
	}
	if cfg.RefreshTokenPurgeInterval <= 0 {
		return nil, fmt.Errorf("config: load: REFRESH_TOKEN_PURGE_INTERVAL must be positive")
	}
	// Le joker CORS convient au developpement (simulateur, Flutter web sur un
	// port quelconque) mais pas a un serveur expose : n'importe quel site
	// pourrait alors appeler l'API depuis le navigateur d'un utilisateur. En
	// production, on exige la liste des origines de la console web.
	if cfg.IsProduction() && !cfg.CORSOriginsAreExplicit() {
		return nil, fmt.Errorf("config: load: CORS_ALLOWED_ORIGINS must list explicit origins when APP_ENV=production")
	}
	return &cfg, nil
}

// CORSOriginsAreExplicit dit si CORS_ALLOWED_ORIGINS ne contient que des
// origines nommees. Un "*" seul ou dans la liste revient a tout accepter
// (c'est ainsi que go-chi/cors l'interprete), une valeur vide n'autorise
// personne : dans les deux cas ce n'est pas une configuration de production.
func (c *Config) CORSOriginsAreExplicit() bool {
	for _, origin := range strings.Split(c.CORSAllowedOrigins, ",") {
		origin = strings.TrimSpace(origin)
		if origin == "" || origin == "*" {
			return false
		}
	}
	return true
}

// PublicBaseURL rend l'URL publique de l'API sans barre finale.
func (c *Config) PublicBaseURL() string {
	if c.PublicBaseURLOverride != "" {
		return strings.TrimRight(c.PublicBaseURLOverride, "/")
	}
	scheme := "http"
	if c.TLSEnabled() {
		scheme = "https"
	}
	return scheme + "://localhost" + c.Addr()
}

// TLSEnabled dit si le serveur principal doit servir en HTTPS.
func (c *Config) TLSEnabled() bool {
	return c.TLSCertFile != "" && c.TLSKeyFile != ""
}

func (c *Config) IsDevelopment() bool {
	return c.AppEnv == "development"
}

func (c *Config) IsProduction() bool {
	return c.AppEnv == "production"
}

func (c *Config) Addr() string {
	return fmt.Sprintf(":%d", c.Port)
}

func (c *Config) MetricsAddr() string {
	return fmt.Sprintf(":%d", c.MetricsPort)
}

func LoadFromEnvFile(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	for _, line := range splitLines(data) {
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		for i := 0; i < len(line); i++ {
			if line[i] == '=' {
				key := string(line[:i])
				val := string(line[i+1:])
				// os.Setenv n'echoue que sur une cle vide ou contenant '='.
				// On coupe a la premiere '=', il ne reste que la cle vide a ecarter.
				if key != "" && os.Getenv(key) == "" {
					_ = os.Setenv(key, val)
				}
				break
			}
		}
	}
}

func splitLines(data []byte) [][]byte {
	var lines [][]byte
	start := 0
	for i := 0; i < len(data); i++ {
		if data[i] == '\n' {
			line := data[start:i]
			if len(line) > 0 && line[len(line)-1] == '\r' {
				line = line[:len(line)-1]
			}
			lines = append(lines, line)
			start = i + 1
		}
	}
	if start < len(data) {
		lines = append(lines, data[start:])
	}
	return lines
}
