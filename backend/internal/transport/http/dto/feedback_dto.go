package dto

import "time"

type SubmitFeedbackRequest struct {
	Type       string `json:"type"`
	Message    string `json:"message"`
	AppVersion string `json:"app_version,omitempty"`
	Platform   string `json:"platform,omitempty"`
}

type UpdateFeedbackStatusRequest struct {
	Status string `json:"status"`
}

type FeedbackResponse struct {
	ID         string    `json:"id"`
	UserID     string    `json:"user_id"`
	Type       string    `json:"type"`
	Message    string    `json:"message"`
	AppVersion string    `json:"app_version,omitempty"`
	Platform   string    `json:"platform,omitempty"`
	Status     string    `json:"status"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}
