package observability

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Valeurs possibles du label "reason" de StreamDisconnections, utilisees a
// la fois ici (pour preenregistrer chaque serie a zero) et dans les
// handlers de streaming qui les incrementent.
const (
	DisconnectReasonClient       = "client"
	DisconnectReasonStreamClosed = "stream_closed"
	DisconnectReasonAbrupt       = "abrupt"
)

var disconnectReasons = []string{DisconnectReasonClient, DisconnectReasonStreamClosed, DisconnectReasonAbrupt}

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
	m := &Metrics{
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

	// Sans appel initial, un CounterVec n'expose aucune serie tant qu'aucun
	// disconnect ne s'est produit pour un "reason" donne : /metrics
	// n'afficherait alors pas stream_disconnections_total du tout. On
	// preenregistre chaque raison a zero pour que la metrique soit toujours
	// visible, comme l'etait l'ancien Counter simple.
	for _, reason := range disconnectReasons {
		m.StreamDisconnections.WithLabelValues(reason)
	}

	return m
}
