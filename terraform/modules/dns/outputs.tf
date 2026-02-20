output "zone_name" {
  description = "The name of the DNS zone"
  value       = google_dns_managed_zone.main.name
}

output "name_servers" {
  description = "Name servers for the DNS zone - configure these in GoDaddy"
  value       = google_dns_managed_zone.main.name_servers
}

output "dns_name" {
  description = "The DNS name of the zone"
  value       = google_dns_managed_zone.main.dns_name
}

output "staging_fqdn" {
  description = "Fully qualified domain name for staging"
  value       = var.staging_ip != null ? "staging.${var.domain}" : null
}
