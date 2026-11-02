variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "n8n_version" {
  type        = string
  default     = "2.45.6"
  description = "Tag of the n8n image, such as \"2.45.6\". Change image_digest with it."

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]*$", var.n8n_version))
    error_message = "n8n_version must be an image tag, such as \"2.45.6\"."
  }
}

variable "image_digest" {
  type        = string
  default     = "sha256:45edf89655fd66dd55ea9336c1791ad14777599fdbf6c5aec6db583ede99a40b"
  description = "Digest of the image for n8n_version, such as \"sha256:45ed...\". Podman pulls by the digest, so a tag that moves upstream can't change what runs."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.image_digest))
    error_message = "image_digest must be a sha256 digest, such as \"sha256:\" followed by 64 hex digits."
  }
}

variable "image_repository" {
  type        = string
  default     = "ghcr.io/n8n-io/n8n"
  description = "Where to pull n8n's image from. \"ghcr.io/n8n-io/n8n\" serves the same image, by the same digest, without Docker Hub's pull limits."

  validation {
    condition     = can(regex("^[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+)+$", var.image_repository))
    error_message = "image_repository must be a registry and path without a tag, such as \"ghcr.io/n8n-io/n8n\"."
  }
}

variable "listen_address" {
  type        = string
  default     = "127.0.0.1"
  description = "Address n8n listens on. The default keeps it on the host for a reverse proxy in front; \"0.0.0.0\" listens on every address."

  validation {
    condition     = can(cidrhost("${var.listen_address}/${strcontains(var.listen_address, ":") ? 128 : 32}", 0))
    error_message = "listen_address must be an IPv4 or IPv6 address, such as \"127.0.0.1\"."
  }
}

variable "port" {
  type        = number
  default     = 5678
  description = "Port n8n listens on."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a whole number from 1 to 65535."
  }
}

variable "public_url" {
  type        = string
  default     = null
  description = "The address people and webhook callers reach n8n at, such as \"https://n8n.example.com\". It sets N8N_HOST, N8N_PROTOCOL, WEBHOOK_URL and N8N_EDITOR_BASE_URL, and an https address turns on secure cookies. When null, n8n builds its URLs from listen_address and port."

  validation {
    condition     = var.public_url == null || can(regex("^https?://[^\\s/:]+(:[0-9]+)?/?$", coalesce(var.public_url, "-")))
    error_message = "public_url must be an http or https address with no path, such as \"https://n8n.example.com\"."
  }
}

variable "proxy_hops" {
  type        = number
  default     = 1
  description = "How many reverse proxies stand in front of n8n. n8n trusts that many X-Forwarded-For entries for the client's address. Set 0 when people reach n8n directly."

  validation {
    condition     = var.proxy_hops >= 0 && floor(var.proxy_hops) == var.proxy_hops
    error_message = "proxy_hops must be a whole number, 0 or more."
  }
}

variable "postgres" {
  type = object({
    host     = optional(string, "127.0.0.1")
    port     = optional(number, 5432)
    database = optional(string, "n8n")
    username = optional(string, "n8n")
    schema   = optional(string, "public")
  })
  default     = null
  description = "PostgreSQL to keep n8n's data in, such as { host = \"db1\" }. The role and database must exist. When null, n8n uses SQLite in /var/lib/n8n/data."

  validation {
    condition     = var.postgres == null || alltrue([for k, v in coalesce(var.postgres, {}) : can(regex("^[A-Za-z0-9_.:-]+$", tostring(v)))])
    error_message = "postgres host, database, username and schema may use letters, digits and . _ - :."
  }
}

variable "postgres_password" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Password of the postgres username. Needed with postgres. Pass it at run time with -var or TF_VAR_postgres_password; it never reaches state or the plan."

  validation {
    condition     = var.postgres == null || length(coalesce(var.postgres_password, "")) > 0
    error_message = "postgres needs postgres_password."
  }

  validation {
    condition     = !strcontains(coalesce(var.postgres_password, "-"), "\n")
    error_message = "postgres_password must be on one line."
  }
}

variable "owner" {
  type = object({
    email      = string
    first_name = optional(string, "Instance")
    last_name  = optional(string, "Owner")
  })
  default     = null
  description = "The owner account to create on the first start, such as { email = \"you@example.com\" }. When null, n8n asks for one the first time you open it."

  validation {
    condition     = var.owner == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", try(var.owner.email, "")))
    error_message = "owner.email must be an email address."
  }

  validation {
    condition     = var.owner == null || (length(try(var.owner.first_name, "")) > 0 && length(try(var.owner.last_name, "")) > 0)
    error_message = "owner.first_name and owner.last_name can't be empty."
  }
}

variable "owner_password" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Password the owner is created with. Needed with owner. n8n wants 8 to 64 characters with a digit and an uppercase letter. Pass it at run time with -var or TF_VAR_owner_password; it never reaches state or the plan."

  validation {
    condition = var.owner == null || (
      length(coalesce(var.owner_password, "")) >= 8 &&
      length(coalesce(var.owner_password, "")) <= 64 &&
      can(regex("[0-9]", coalesce(var.owner_password, "-"))) &&
      can(regex("[A-Z]", coalesce(var.owner_password, "-"))) &&
      !strcontains(coalesce(var.owner_password, "-"), "\n")
    )
    error_message = "owner needs an owner_password of 8 to 64 characters, on one line, with at least one digit and one uppercase letter."
  }
}

variable "executions_prune" {
  type        = bool
  default     = true
  description = "Delete old execution data, so the database doesn't grow without end. Sets EXECUTIONS_DATA_PRUNE."
}

variable "executions_max_age" {
  type        = number
  default     = 336
  description = "Hours to keep finished executions for before pruning deletes them. Sets EXECUTIONS_DATA_MAX_AGE. The default is two weeks, as in n8n."

  validation {
    condition     = var.executions_max_age >= 1 && floor(var.executions_max_age) == var.executions_max_age
    error_message = "executions_max_age must be a whole number of hours, 1 or more."
  }
}

variable "environment" {
  type        = map(string)
  default     = {}
  ephemeral   = true
  sensitive   = true
  nullable    = false
  description = "More of n8n's environment variables, such as { GENERIC_TIMEZONE = \"Europe/London\", N8N_SMTP_PASS = \"...\" }. They go in a root-only env file and never reach the plan or state."

  validation {
    condition     = alltrue([for k, v in var.environment : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && !strcontains(v, "\n")])
    error_message = "environment maps variable names, such as GENERIC_TIMEZONE, to values on one line."
  }

  validation {
    condition = length(setintersection(keys(var.environment), [
      "N8N_ENCRYPTION_KEY", "N8N_ENCRYPTION_KEY_FILE", "N8N_LISTEN_ADDRESS", "N8N_PORT", "N8N_HOST", "N8N_PROTOCOL",
      "WEBHOOK_URL", "N8N_EDITOR_BASE_URL", "N8N_SECURE_COOKIE", "N8N_PROXY_HOPS",
      "N8N_DIAGNOSTICS_ENABLED", "N8N_PERSONALIZATION_ENABLED", "N8N_VERSION_NOTIFICATIONS_ENABLED",
      "EXECUTIONS_DATA_PRUNE", "EXECUTIONS_DATA_MAX_AGE", "DB_TYPE", "DB_POSTGRESDB_HOST", "DB_POSTGRESDB_PORT",
      "DB_POSTGRESDB_DATABASE", "DB_POSTGRESDB_USER", "DB_POSTGRESDB_PASSWORD", "DB_POSTGRESDB_SCHEMA",
    ])) == 0
    error_message = "Set the listen address, port, URLs, database and pruning with their own inputs. N8N_ENCRYPTION_KEY is generated on the host, and telemetry and version checks stay off."
  }
}
