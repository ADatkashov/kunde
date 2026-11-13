variable "repo_url" {
  description = "Public GitHub repository Render builds from."
  type        = string
  default     = "https://github.com/ADatkashov/kunde"
}

variable "branch" {
  type    = string
  default = "main"
}

variable "neon_org_id" {
  description = "Neon organization id (null for a personal account)."
  type        = string
  default     = null
}

variable "oidc_issuer_uri" {
  type    = string
  default = ""
}

variable "oidc_audience" {
  type    = string
  default = ""
}
