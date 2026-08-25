package config

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/sethvargo/go-envconfig"
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
	CORSAllowedOrigins string        `env:"CORS_ALLOWED_ORIGINS,default=*"`
	RateLimitRPS       float64       `env:"RATE_LIMIT_RPS,default=10"`
	RateLimitBurst     int           `env:"RATE_LIMIT_BURST,default=20"`
}

func Load() (*Config, error) {
	var cfg Config
	if err := envconfig.Process(context.Background(), &cfg); err != nil {
		return nil, fmt.Errorf("config: load: %w", err)
	}
	return &cfg, nil
}

func (c *Config) IsDevelopment() bool {
	return c.AppEnv == "development"
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
