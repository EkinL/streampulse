package chat

import (
	"encoding/json"
	"fmt"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/streampulse/backend/internal/infrastructure/streaming"
)

func newTestHub() *Hub {
	return NewHub(zerolog.Nop())
}

func newParticipant(name string) *streaming.Client {
	return streaming.NewClient(uuid.New(), name)
}

// drain lit tous les messages deja en file pour ce participant.
func drain(t *testing.T, c *streaming.Client) []Message {
	t.Helper()
	var msgs []Message
	for {
		select {
		case data := <-c.Ch:
			var m Message
			if err := json.Unmarshal(data, &m); err != nil {
				t.Fatalf("invalid message JSON: %v", err)
			}
			msgs = append(msgs, m)
		default:
			return msgs
		}
	}
}

// discard vide la file d'un participant sans verifier (utilisable hors de la
// goroutine du test, contrairement a drain qui peut appeler t.Fatalf).
func discard(c *streaming.Client) {
	for {
		select {
		case <-c.Ch:
		default:
			return
		}
	}
}

func TestPublishFanOut(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()
	alice := newParticipant("alice")
	bob := newParticipant("bob")
	hub.Join(streamID, alice)
	hub.Join(streamID, bob)

	msg := NewUserMessage(streamID, alice.UserID, "alice", "salut")
	hub.Publish(streamID, msg)

	for _, c := range []*streaming.Client{alice, bob} {
		got := drain(t, c)
		if len(got) != 1 || got[0].Text != "salut" || got[0].Type != TypeMessage {
			t.Fatalf("%s: got %+v, want one 'salut' message", c.Username, got)
		}
	}
}

func TestPublishDoesNotCrossStreams(t *testing.T) {
	hub := newTestHub()
	streamA, streamB := uuid.New(), uuid.New()
	alice := newParticipant("alice")
	bob := newParticipant("bob")
	hub.Join(streamA, alice)
	hub.Join(streamB, bob)

	hub.Publish(streamA, NewUserMessage(streamA, alice.UserID, "alice", "prive"))

	if got := drain(t, bob); len(got) != 0 {
		t.Fatalf("bob is in another room but received %+v", got)
	}
}

func TestJoinReplaysHistoryInOrder(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()
	alice := newParticipant("alice")
	hub.Join(streamID, alice)

	for i := 0; i < 3; i++ {
		hub.Publish(streamID, NewUserMessage(streamID, alice.UserID, "alice", fmt.Sprintf("msg-%d", i)))
	}

	late := newParticipant("late")
	hub.Join(streamID, late)

	got := drain(t, late)
	if len(got) != 3 {
		t.Fatalf("late joiner got %d messages, want 3", len(got))
	}
	for i, m := range got {
		if want := fmt.Sprintf("msg-%d", i); m.Text != want {
			t.Errorf("history[%d] = %q, want %q", i, m.Text, want)
		}
	}
}

func TestHistoryKeepsOnlyLastMessages(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()
	alice := newParticipant("alice")
	hub.Join(streamID, alice)

	total := historyLimit + 10
	for i := 0; i < total; i++ {
		hub.Publish(streamID, NewUserMessage(streamID, alice.UserID, "alice", fmt.Sprintf("msg-%d", i)))
	}

	late := newParticipant("late")
	hub.Join(streamID, late)

	got := drain(t, late)
	if len(got) != historyLimit {
		t.Fatalf("late joiner got %d messages, want %d", len(got), historyLimit)
	}
	if want := fmt.Sprintf("msg-%d", total-historyLimit); got[0].Text != want {
		t.Errorf("oldest kept message = %q, want %q", got[0].Text, want)
	}
	if want := fmt.Sprintf("msg-%d", total-1); got[len(got)-1].Text != want {
		t.Errorf("newest kept message = %q, want %q", got[len(got)-1].Text, want)
	}
}

func TestPresenceEventsAreNotStored(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()
	alice := newParticipant("alice")
	hub.Join(streamID, alice)

	hub.Publish(streamID, NewPresenceMessage(TypeUserJoined, streamID, alice.UserID, "alice"))
	hub.Publish(streamID, NewPresenceMessage(TypeUserLeft, streamID, alice.UserID, "alice"))

	late := newParticipant("late")
	hub.Join(streamID, late)

	if got := drain(t, late); len(got) != 0 {
		t.Fatalf("presence events ended up in history: %+v", got)
	}
}

func TestLastLeaveDropsRoom(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()
	alice := newParticipant("alice")
	bob := newParticipant("bob")
	hub.Join(streamID, alice)
	hub.Join(streamID, bob)

	hub.Leave(streamID, alice)
	if got := hub.Participants(streamID); got != 1 {
		t.Fatalf("participants = %d, want 1", got)
	}
	hub.Leave(streamID, bob)
	if got := hub.ActiveRooms(); got != 0 {
		t.Fatalf("active rooms = %d, want 0 (room must die with its last participant)", got)
	}
}

func TestCloseStreamDisconnectsEveryone(t *testing.T) {
	hub := newTestHub()
	streamID := uuid.New()
	alice := newParticipant("alice")
	bob := newParticipant("bob")
	hub.Join(streamID, alice)
	hub.Join(streamID, bob)

	hub.CloseStream(streamID)

	for _, c := range []*streaming.Client{alice, bob} {
		select {
		case <-c.Done():
		default:
			t.Fatalf("%s was not closed by CloseStream", c.Username)
		}
	}
	if got := hub.ActiveRooms(); got != 0 {
		t.Fatalf("active rooms = %d, want 0", got)
	}
}

// TestConcurrentChurn : arrivees, departs et publications concurrentes sur
// plusieurs salons, sous -race. A la fin, plus aucun salon ne doit rester.
func TestConcurrentChurn(t *testing.T) {
	hub := newTestHub()
	streams := []uuid.UUID{uuid.New(), uuid.New(), uuid.New()}

	var wg sync.WaitGroup
	for i := 0; i < 30; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			streamID := streams[i%len(streams)]
			c := newParticipant(fmt.Sprintf("user-%d", i))
			hub.Join(streamID, c)
			for j := 0; j < 20; j++ {
				hub.Publish(streamID, NewUserMessage(streamID, c.UserID, c.Username, "x"))
				discard(c)
			}
			hub.Leave(streamID, c)
		}(i)
	}
	wg.Wait()

	if got := hub.ActiveRooms(); got != 0 {
		t.Fatalf("active rooms = %d after churn, want 0", got)
	}
}
