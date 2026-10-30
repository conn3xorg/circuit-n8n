variable "port" {
  type    = number
  default = 2222
}

# Example password only. Pass your own with -var or TF_VAR_ on a real host.
variable "owner_password" {
  type      = string
  default   = "Correct-horse-battery-9"
  ephemeral = true
  sensitive = true
}

# Docker Hub limits how often you can pull without an account. Set this to
# "ghcr.io/n8n-io/n8n" if you hit the limit.
variable "image_repository" {
  type    = string
  default = "docker.n8n.io/n8nio/n8n"
}

module "n8n" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  image_repository = var.image_repository
  owner            = { email = "owner@example.com" }
  owner_password   = var.owner_password
}
