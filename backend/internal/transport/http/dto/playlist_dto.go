package dto

import "time"

type CreatePlaylistRequest struct {
	Name     string `json:"name"`
	IsPublic bool   `json:"is_public"`
}

type UpdatePlaylistRequest struct {
	Name     string `json:"name"`
	IsPublic bool   `json:"is_public"`
}

type AddTrackRequest struct {
	Title    string `json:"title"`
	URL      string `json:"url"`
	Duration int    `json:"duration"`
}

// ReorderTracksRequest carries the complete track list in the desired order.
type ReorderTracksRequest struct {
	TrackIDs []string `json:"track_ids"`
}

type PlaylistResponse struct {
	ID        string          `json:"id"`
	Name      string          `json:"name"`
	OwnerID   string          `json:"owner_id"`
	IsPublic  bool            `json:"is_public"`
	Tracks    []TrackResponse `json:"tracks,omitempty"`
	CreatedAt time.Time       `json:"created_at"`
	UpdatedAt time.Time       `json:"updated_at"`
}

type TrackResponse struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	URL      string `json:"url"`
	Duration int    `json:"duration"`
	Position int    `json:"position"`
}
