package dto

import "time"

type MusicResponse struct {
	ID         string    `json:"id"`
	Title      string    `json:"title"`
	Artist     string    `json:"artist"`
	Album      string    `json:"album"`
	Duration   int       `json:"duration"`
	URL        string    `json:"url"`
	CoverURL   string    `json:"cover_url"`
	UploadedBy string    `json:"uploaded_by"`
	CreatedAt  time.Time `json:"created_at"`
}

type UpdateMusicRequest struct {
	Title    string `json:"title"`
	Artist   string `json:"artist"`
	Album    string `json:"album"`
	CoverURL string `json:"cover_url"`
}

type AddMusicURLRequest struct {
	Title    string `json:"title"`
	Artist   string `json:"artist"`
	Album    string `json:"album"`
	Duration int    `json:"duration"`
	URL      string `json:"url"`
}

type SearchResponse struct {
	Streams []StreamResponse `json:"streams"`
	Music   []MusicResponse  `json:"music"`
}
