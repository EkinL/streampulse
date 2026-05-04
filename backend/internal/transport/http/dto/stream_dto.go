package dto

import "time"

type CreateStreamRequest struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Format      string `json:"format"`
}

type UpdateStreamRequest struct {
	Title       string `json:"title"`
	Description string `json:"description"`
}

type StreamResponse struct {
	ID            string    `json:"id"`
	Title         string    `json:"title"`
	Description   string    `json:"description"`
	OwnerID       string    `json:"owner_id"`
	Status        string    `json:"status"`
	ListenerCount int       `json:"listener_count"`
	Format        string    `json:"format"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}
