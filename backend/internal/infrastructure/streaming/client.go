package streaming

import (
	"sync"
	"sync/atomic"

	"github.com/google/uuid"
)

const clientBufferSize = 256

type Client struct {
	ID       uuid.UUID
	UserID   uuid.UUID
	Username string
	Ch       chan []byte
	done     chan struct{}
	once     sync.Once
	dropped  atomic.Int64
}

func NewClient(userID uuid.UUID, username string) *Client {
	return &Client{
		ID:       uuid.New(),
		UserID:   userID,
		Username: username,
		Ch:       make(chan []byte, clientBufferSize),
		done:     make(chan struct{}),
	}
}

func (c *Client) Send(data []byte) bool {
	select {
	case <-c.done:
		return false
	default:
	}

	buf := make([]byte, len(data))
	copy(buf, data)

	select {
	case c.Ch <- buf:
		return true
	case <-c.done:
		return false
	default:
		// Tampon plein : l'auditeur est trop lent, le chunk est jete plutot
		// que de bloquer le diffuseur. Comptabilise pour le SLI de SLO 4
		// (docs/slo.md) sans changer la valeur de retour : renvoyer false
		// ici desinscrirait le client du Hub, ce qui n'est pas le but.
		c.dropped.Add(1)
		return true
	}
}

// Dropped renvoie le nombre de chunks jetes pour ce client depuis sa
// creation, faute de place dans son tampon.
func (c *Client) Dropped() int64 {
	return c.dropped.Load()
}

func (c *Client) Close() {
	c.once.Do(func() {
		close(c.done)
	})
}

func (c *Client) Done() <-chan struct{} {
	return c.done
}
