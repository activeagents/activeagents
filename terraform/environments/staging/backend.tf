terraform {
  backend "gcs" {
    bucket = "active-agents-platform-terraform-state"
    prefix = "staging"
  }
}
