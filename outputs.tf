output "service" {
  description = "The systemd service that runs n8n on each host."
  value       = "n8n.service"
}

output "image" {
  description = "The n8n image the hosts run."
  value       = local.image
}

output "url" {
  description = "Where n8n answers on each host itself, such as \"http://127.0.0.1:5678\". Point a reverse proxy here."
  value       = local.local_url
}

output "keys_file" {
  description = "File on each host holding the generated N8N_ENCRYPTION_KEY. Back it up: without it, no credential n8n stores can be decrypted."
  value       = local.keys_file
}
