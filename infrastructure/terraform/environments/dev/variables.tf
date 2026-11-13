variable "repo_url" {
  description = "Public GitHub repository Render builds from."
  type        = string
  default     = "https://github.com/ADatkashov/kunde"
}

variable "neon_project_name" {
  type    = string
  default = "kunde-dev"
}

variable "render_service_name" {
  type    = string
  default = "kunde-backend"
}

variable "branch" {
  type    = string
  default = "main"
}

variable "neon_org_id" {
  description = "Neon organization id (org-...); required for organization-owned accounts. Set via TF_VAR_neon_org_id (GitHub variable), not committed."
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
