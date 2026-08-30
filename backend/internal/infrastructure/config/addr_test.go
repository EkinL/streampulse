package config

import "testing"

func TestAddrAndMetricsAddr(t *testing.T) {
	cfg := &Config{Port: 8080, MetricsPort: 9091}
	if got := cfg.Addr(); got != ":8080" {
		t.Errorf("Addr() = %q, attendu :8080", got)
	}
	if got := cfg.MetricsAddr(); got != ":9091" {
		t.Errorf("MetricsAddr() = %q, attendu :9091", got)
	}
}
