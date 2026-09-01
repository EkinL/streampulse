package observability

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

type Metrics struct {
	HTTPRequestsTotal    *prometheus.CounterVec
	HTTPRequestDuration  *prometheus.HistogramVec
	ActiveStreams        prometheus.Gauge
	ActiveListeners      prometheus.Gauge
	StreamDisconnections prometheus.Counter
	StreamBytesSentTotal prometheus.Counter
}

func NewMetrics() *Metrics {
	return &Metrics{
		HTTPRequestsTotal: promauto.NewCounterVec(
			prometheus.CounterOpts{
				Name: "http_requests_total",
				Help: "Total number of HTTP requests",
			},
			[]string{"method", "path", "status"},
		),
		HTTPRequestDuration: promauto.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "http_request_duration_seconds",
				Help:    "HTTP request duration in seconds",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"method", "path"},
		),
		ActiveStreams: promauto.NewGauge(
			prometheus.GaugeOpts{
				Name: "active_streams",
				Help: "Number of currently active streams",
			},
		),
		ActiveListeners: promauto.NewGauge(
			prometheus.GaugeOpts{
				Name: "active_listeners",
				Help: "Number of currently connected listeners",
			},
		),
		StreamDisconnections: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "stream_disconnections_total",
				Help: "Total number of stream disconnections",
			},
		),
		StreamBytesSentTotal: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "stream_bytes_sent_total",
				Help: "Total bytes sent to stream listeners",
			},
		),
	}
}
