package observability

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

type Metrics struct {
	HTTPRequestsTotal     *prometheus.CounterVec
	HTTPRequestDuration   *prometheus.HistogramVec
	ActiveStreams         prometheus.Gauge
	ActiveListeners       prometheus.Gauge
	StreamDisconnections  *prometheus.CounterVec
	StreamBytesSentTotal  prometheus.Counter
	ListenerSessions      prometheus.Counter
	SessionsWithChunkLoss prometheus.Counter
	ChatConnections       prometheus.Gauge
	ChatMessagesTotal     prometheus.Counter
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
		StreamDisconnections: promauto.NewCounterVec(
			prometheus.CounterOpts{
				Name: "stream_disconnections_total",
				Help: "Total number of stream disconnections, labeled by reason",
			},
			[]string{"reason"},
		),
		StreamBytesSentTotal: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "stream_bytes_sent_total",
				Help: "Total bytes sent to stream listeners",
			},
		),
		ListenerSessions: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "listener_sessions_total",
				Help: "Total number of listening sessions",
			},
		),
		SessionsWithChunkLoss: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "sessions_with_chunk_loss_total",
				Help: "Total number of listening sessions that dropped at least one audio chunk",
			},
		),
		ChatConnections: promauto.NewGauge(
			prometheus.GaugeOpts{
				Name: "chat_active_connections",
				Help: "Number of currently connected chat participants",
			},
		),
		ChatMessagesTotal: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "chat_messages_total",
				Help: "Total number of chat messages published",
			},
		),
	}
}
