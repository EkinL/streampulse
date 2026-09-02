package streaming

import (
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog"
)

// Les tests de ce fichier prouvent la tenue en charge du Hub de fan-out
// (goroutines + channels) : chaque auditeur a sa goroutine qui draine son
// channel, le diffuseur pousse des chunks, et on verifie qu'aucun auditeur
// ne bloque les autres et qu'aucun chunk n'est perdu tant que l'auditeur
// suit le rythme.

const chunkSize = 4096 // meme taille que le buffer de lecture du handler Broadcast

func newTestHub() *Hub {
	return NewHub(zerolog.Nop())
}

// drain consomme le channel d'un client dans sa propre goroutine, comme le
// fait le handler SSE, et compte les chunks et les octets recus.
type drain struct {
	chunks atomic.Int64
	bytes  atomic.Int64
	done   chan struct{}
}

func startDrain(wg *sync.WaitGroup, c *Client) *drain {
	d := &drain{done: make(chan struct{})}
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-d.done:
				return
			case <-c.Done():
				return
			case data := <-c.Ch:
				d.chunks.Add(1)
				d.bytes.Add(int64(len(data)))
			}
		}
	}()
	return d
}

func registerListeners(hub *Hub, streamID uuid.UUID, n int) []*Client {
	clients := make([]*Client, n)
	for i := range clients {
		clients[i] = NewClient(uuid.New(), fmt.Sprintf("listener-%d", i))
		hub.Register(streamID, clients[i])
	}
	return clients
}

// waitFor attend qu'une condition devienne vraie, sans sleep fixe.
func waitFor(t *testing.T, timeout time.Duration, cond func() bool, msg string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timeout after %s: %s", timeout, msg)
}

// TestHubFanOutNListeners : N auditeurs concurrents recoivent chacun
// l'integralite des chunks diffuses. C'est la preuve d'encaisser N auditeurs
// au niveau du Hub, sans la couche HTTP.
func TestHubFanOutNListeners(t *testing.T) {
	listeners := 1000
	chunks := 200 // < clientBufferSize : aucun drop possible, meme si un auditeur est lent
	if testing.Short() {
		listeners = 100
	}

	hub := newTestHub()
	streamID := uuid.New()
	clients := registerListeners(hub, streamID, listeners)

	var wg sync.WaitGroup
	drains := make([]*drain, len(clients))
	for i, c := range clients {
		drains[i] = startDrain(&wg, c)
	}

	if got := hub.ListenerCount(streamID); got != listeners {
		t.Fatalf("ListenerCount = %d, want %d", got, listeners)
	}

	payload := make([]byte, chunkSize)
	start := time.Now()
	for i := 0; i < chunks; i++ {
		hub.Broadcast(streamID, payload)
	}
	elapsed := time.Since(start)

	wantBytes := int64(chunks * chunkSize)
	waitFor(t, 10*time.Second, func() bool {
		for _, d := range drains {
			if d.bytes.Load() < wantBytes {
				return false
			}
		}
		return true
	}, "not every listener received the full payload")

	for i, d := range drains {
		if got := d.chunks.Load(); got != int64(chunks) {
			t.Errorf("listener %d received %d chunks, want %d", i, got, chunks)
		}
	}

	totalMB := float64(wantBytes*int64(listeners)) / (1024 * 1024)
	t.Logf("%d listeners x %d chunks of %d B = %.1f MiB fanned out in %s (%.0f MiB/s)",
		listeners, chunks, chunkSize, totalMB, elapsed, totalMB/elapsed.Seconds())

	for _, d := range drains {
		close(d.done)
	}
	wg.Wait()

	for _, c := range clients {
		hub.Unregister(streamID, c)
	}
	if got := hub.ListenerCount(streamID); got != 0 {
		t.Fatalf("ListenerCount after unregister = %d, want 0", got)
	}
	if got := hub.ActiveStreams(); got != 0 {
		t.Fatalf("ActiveStreams after unregister = %d, want 0", got)
	}
}

// TestHubSlowListenerDoesNotBlockOthers : un auditeur qui ne lit jamais son
// channel ne doit ni bloquer Broadcast ni priver les autres auditeurs.
// Send est non bloquant : quand le buffer est plein, le chunk est perdu
// pour ce seul auditeur (cf. client.go).
func TestHubSlowListenerDoesNotBlockOthers(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()

	slow := NewClient(uuid.New(), "slow")
	hub.Register(streamID, slow)

	fast := registerListeners(hub, streamID, 10)
	var wg sync.WaitGroup
	drains := make([]*drain, len(fast))
	for i, c := range fast {
		drains[i] = startDrain(&wg, c)
	}

	chunks := clientBufferSize * 4 // le buffer du client lent deborde largement
	payload := make([]byte, chunkSize)

	broadcastDone := make(chan struct{})
	go func() {
		defer close(broadcastDone)
		for i := 0; i < chunks; i++ {
			hub.Broadcast(streamID, payload)
		}
	}()

	select {
	case <-broadcastDone:
	case <-time.After(10 * time.Second):
		t.Fatal("Broadcast blocked on a slow listener")
	}

	waitFor(t, 10*time.Second, func() bool {
		for _, d := range drains {
			if d.chunks.Load() < int64(chunks) {
				return false
			}
		}
		return true
	}, "fast listeners did not receive every chunk")

	if len(slow.Ch) != clientBufferSize {
		t.Fatalf("slow listener buffer = %d, want it full at %d", len(slow.Ch), clientBufferSize)
	}
	// Le lent est toujours enregistre : il n'est evince que s'il se deconnecte.
	if got := hub.ListenerCount(streamID); got != len(fast)+1 {
		t.Fatalf("ListenerCount = %d, want %d", got, len(fast)+1)
	}
	// Chaque chunk au-dela du tampon plein est jete et compte, cf. SLO 4
	// (docs/slo.md) : le lent en a rate chunks-clientBufferSize au minimum.
	if got, want := slow.Dropped(), int64(chunks-clientBufferSize); got < want {
		t.Fatalf("slow.Dropped() = %d, want at least %d", got, want)
	}
	for _, c := range fast {
		if got := c.Dropped(); got != 0 {
			t.Fatalf("fast listener dropped %d chunks, want 0", got)
		}
	}

	for _, d := range drains {
		close(d.done)
	}
	wg.Wait()
}

// TestHubBroadcastEvictsClosedClient : un client ferme (deconnexion brutale)
// est retire du Hub au broadcast suivant, ce qui nourrit la metrique
// stream_disconnections_total cote handler.
func TestHubBroadcastEvictsClosedClient(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()

	var changes []int
	hub.OnListenerChange = func(_ uuid.UUID, count int) { changes = append(changes, count) }

	clients := registerListeners(hub, streamID, 3)
	clients[1].Close()

	hub.Broadcast(streamID, []byte("x"))

	if got := hub.ListenerCount(streamID); got != 2 {
		t.Fatalf("ListenerCount = %d, want 2 after evicting the closed client", got)
	}
	// Send sur un client ferme doit signaler l'echec : c'est ce qui declenche l'eviction.
	if clients[1].Send([]byte("y")) {
		t.Fatal("Send on a closed client returned true")
	}
	if len(changes) != 4 || changes[3] != 2 {
		t.Fatalf("OnListenerChange calls = %v, want [1 2 3 2]", changes)
	}
}

// TestHubCloseStream : arreter un flux ferme tous ses auditeurs d'un coup.
func TestHubCloseStream(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()
	other := uuid.New()

	clients := registerListeners(hub, streamID, 5)
	hub.Register(other, NewClient(uuid.New(), "elsewhere"))

	hub.CloseStream(streamID)

	for i, c := range clients {
		select {
		case <-c.Done():
		default:
			t.Fatalf("client %d not closed by CloseStream", i)
		}
	}
	if got := hub.ListenerCount(streamID); got != 0 {
		t.Fatalf("ListenerCount = %d, want 0", got)
	}
	if got := hub.ActiveStreams(); got != 1 {
		t.Fatalf("ActiveStreams = %d, want 1 (the other stream is untouched)", got)
	}
	if got := hub.TotalListeners(); got != 1 {
		t.Fatalf("TotalListeners = %d, want 1", got)
	}
	// Idempotent : refermer un flux inconnu ne panique pas.
	hub.CloseStream(streamID)
}

// TestHubConcurrentChurn : auditeurs qui arrivent et partent pendant que le
// diffuseur emet, sur plusieurs flux. Sous -race, ce test detecte tout acces
// non synchronise ; a la fin le Hub doit etre vide (aucune fuite d'entree).
func TestHubConcurrentChurn(t *testing.T) {
	hub := newTestHub()
	streams := []uuid.UUID{uuid.New(), uuid.New(), uuid.New()}
	payload := make([]byte, 512)

	stop := make(chan struct{})
	var wg sync.WaitGroup

	// Diffuseurs : un par flux, en boucle jusqu'au stop.
	for _, id := range streams {
		wg.Add(1)
		go func(id uuid.UUID) {
			defer wg.Done()
			for {
				select {
				case <-stop:
					return
				default:
					hub.Broadcast(id, payload)
				}
			}
		}(id)
	}

	// Auditeurs : chacun rejoint un flux, lit un peu, puis part.
	const listeners = 200
	for i := 0; i < listeners; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			id := streams[i%len(streams)]
			c := NewClient(uuid.New(), fmt.Sprintf("churn-%d", i))
			hub.Register(id, c)
			for n := 0; n < 20; n++ {
				select {
				case <-c.Ch:
				case <-time.After(50 * time.Millisecond):
				}
			}
			if i%2 == 0 {
				c.Close() // deconnexion brutale : le Hub doit l'evincer seul
			} else {
				hub.Unregister(id, c)
			}
		}(i)
	}

	// Lecteurs d'etat concurrents (ce que font GetStream / GetListeners).
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
				hub.TotalListeners()
				hub.ActiveStreams()
				hub.Listeners(streams[0])
			}
		}
	}()

	time.Sleep(300 * time.Millisecond)
	close(stop)
	wg.Wait()

	// Un dernier broadcast evince les clients fermes brutalement.
	for _, id := range streams {
		hub.Broadcast(id, payload)
	}
	if got := hub.TotalListeners(); got != 0 {
		t.Fatalf("TotalListeners = %d, want 0 after churn", got)
	}
	if got := hub.ActiveStreams(); got != 0 {
		t.Fatalf("ActiveStreams = %d, want 0 after churn", got)
	}
}

// BenchmarkHubBroadcast mesure le cout d'un chunk de 4 KiB diffuse a N
// auditeurs qui drainent en parallele. b.SetBytes donne le debit par
// auditeur ; la metrique ns/listener donne le cout marginal d'un auditeur.
//
//	go test -run '^$' -bench 'Hub' -benchmem ./internal/infrastructure/streaming/
func BenchmarkHubBroadcast(b *testing.B) {
	for _, n := range []int{10, 100, 1000, 10000} {
		b.Run(fmt.Sprintf("listeners=%d", n), func(b *testing.B) {
			hub := newTestHub()
			streamID := uuid.New()
			clients := registerListeners(hub, streamID, n)

			var wg sync.WaitGroup
			drains := make([]*drain, n)
			for i, c := range clients {
				drains[i] = startDrain(&wg, c)
			}

			payload := make([]byte, chunkSize)
			b.SetBytes(int64(chunkSize * n))
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				hub.Broadcast(streamID, payload)
			}
			b.StopTimer()
			b.ReportMetric(float64(b.Elapsed().Nanoseconds())/float64(b.N)/float64(n), "ns/listener")

			for _, d := range drains {
				close(d.done)
			}
			wg.Wait()
		})
	}
}

// BenchmarkHubRegisterUnregister mesure le cout d'une connexion/deconnexion
// d'auditeur sur un flux qui en compte deja 1000.
func BenchmarkHubRegisterUnregister(b *testing.B) {
	hub := newTestHub()
	streamID := uuid.New()
	registerListeners(hub, streamID, 1000)

	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		c := NewClient(uuid.Nil, "bench")
		hub.Register(streamID, c)
		hub.Unregister(streamID, c)
	}
}
