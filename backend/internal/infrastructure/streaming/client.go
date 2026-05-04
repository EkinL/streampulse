package streaming

import (
	"sync"

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
		return true
	}
}

func (c *Client) Close() {
	c.once.Do(func() {
		close(c.done)
	})
}

func (c *Client) Done() <-chan struct{} {
	return c.done
}
