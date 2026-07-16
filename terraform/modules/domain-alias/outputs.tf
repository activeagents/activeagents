output "name_servers" {
  description = "Cloud DNS name servers — delegate the domain to these at its registrar"
  value       = google_dns_managed_zone.alias.name_servers
}

output "zone_name" {
  description = "Cloud DNS zone name"
  value       = google_dns_managed_zone.alias.name
}
