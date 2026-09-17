variable "instruqt_session_id" {
  type        = string
  description = "Reserved: unique ID for this lab session, provided by the platform"
}

variable "instruqt_team_id" {
  type        = string
  description = "Reserved: ID of the team running this session, provided by the platform"
}

variable "instruqt_team_slug" {
  type        = string
  description = "Reserved: slug of the team running this session, provided by the platform"
}

variable "instruqt_lab_id" {
  type        = string
  description = "Reserved: ID of this lab, provided by the platform"
}

variable "instruqt_lab_slug" {
  type        = string
  description = "Reserved: slug of this lab, provided by the platform"
}

variable "instruqt_user_id" {
  type        = string
  description = "Reserved: ID of the learner running this session, provided by the platform"
}

variable "instruqt_sandbox_domain" {
  type        = string
  description = "Reserved: base domain used to construct public URLs for this sandbox, provided by the platform"
}
