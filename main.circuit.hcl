locals {
  image     = "${var.image_repository}:${var.n8n_version}@${var.image_digest}"
  etc       = "/etc/n8n"
  data      = "/var/lib/n8n"
  keys_file = "/etc/n8n/keys.env"

  # [scheme, host] of public_url.
  public = var.public_url == null ? null : regex("^(https?)://([^/:]+)", var.public_url)
  tls    = try(local.public[0], "http") == "https"

  local_host = lookup({ "0.0.0.0" = "127.0.0.1", "::" = "[::1]" }, var.listen_address, strcontains(var.listen_address, ":") ? "[${var.listen_address}]" : var.listen_address)
  local_url  = "http://${local.local_host}:${var.port}"

  environment = merge(
    {
      N8N_LISTEN_ADDRESS = var.listen_address
      N8N_PORT           = tostring(var.port)
      # Browsers only send a secure cookie over HTTPS, so with plain HTTP
      # nobody could sign in.
      N8N_SECURE_COOKIE = tostring(local.tls)
      N8N_PROXY_HOPS    = tostring(var.proxy_hops)
      # n8n sends telemetry and checks for new versions unless told not to.
      # Upgrades go through n8n_version anyway.
      N8N_DIAGNOSTICS_ENABLED           = "false"
      N8N_PERSONALIZATION_ENABLED       = "false"
      N8N_VERSION_NOTIFICATIONS_ENABLED = "false"
      EXECUTIONS_DATA_PRUNE             = tostring(var.executions_prune)
      EXECUTIONS_DATA_MAX_AGE           = tostring(var.executions_max_age)
    },
    var.public_url == null ? {} : {
      N8N_HOST            = local.public[1]
      N8N_PROTOCOL        = local.public[0]
      WEBHOOK_URL         = "${trimsuffix(var.public_url, "/")}/"
      N8N_EDITOR_BASE_URL = "${trimsuffix(var.public_url, "/")}/"
    },
    var.postgres == null ? {} : {
      DB_TYPE                = "postgresdb"
      DB_POSTGRESDB_HOST     = var.postgres.host
      DB_POSTGRESDB_PORT     = tostring(var.postgres.port)
      DB_POSTGRESDB_DATABASE = var.postgres.database
      DB_POSTGRESDB_USER     = var.postgres.username
      DB_POSTGRESDB_SCHEMA   = var.postgres.schema
    },
  )

  # Run in the n8n container by the owner step, since the host may have no
  # curl. The password comes in on stdin, so it's in no command line.
  owner_script = var.owner == null ? "" : <<-EOT
    // Written by Conn3x. Creates n8n's owner account once.
    import { readFileSync } from "node:fs";
    const owner = ${jsonencode({ email = var.owner.email, firstName = var.owner.first_name, lastName = var.owner.last_name })};
    const base = ${jsonencode(local.local_url)};
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    // Until n8n's API is up, the editor's HTML answers instead of JSON.
    const read = () => fetch(base + "/rest/settings").then((r) => r.json(), () => null).catch(() => null);
    let settings;
    for (let i = 0; !(settings = await read()); i++) {
      if (i === 300) {
        console.error("n8n's API didn't answer in 5 minutes. See journalctl -u n8n.");
        process.exit(1);
      }
      await sleep(1000);
    }
    if (!settings.data.userManagement.showSetupOnFirstLoad) {
      console.log("n8n already has an owner. Leaving it as it is.");
      process.exit(0);
    }
    const res = await fetch(base + "/rest/owner/setup", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...owner, password: readFileSync(0, "utf8") }),
    });
    if (!res.ok) {
      console.error(`n8n refused the owner: $${res.status} $${await res.text()}`);
      process.exit(1);
    }
    console.log("Created the owner.");
  EOT
}

circuit "n8n" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "etc" {
    directory {
      path  = local.etc
      owner = "root"
      group = "root"
      mode  = "0700"
    }
  }

  # N8N_ENCRYPTION_KEY encrypts every credential n8n stores. It's made on
  # the host by the first apply and never passes through Conn3x, so it's in
  # neither the plan nor state. creates keeps it from ever being replaced: a
  # new key would leave every stored credential unreadable. 24 random bytes
  # in base64 is what n8n makes for itself when it has none.
  step "key" {
    command {
      command = "umask 077 && printf 'N8N_ENCRYPTION_KEY=%s\\n' \"$(head -c 24 /dev/urandom | base64)\" > ${local.keys_file}.new && mv ${local.keys_file}.new ${local.keys_file}"
      creates = local.keys_file
    }
  }

  # The SQLite database, n8n's config and binary data. Podman hands it to
  # the container's node user, UID 1000, as it starts (the :U below), so
  # the owner isn't set here.
  step "data" {
    directory {
      path = local.data
      mode = "0700"
    }
  }
}

# n8n runs from its official image as a Quadlet unit. It's on the host's
# network so it can reach a PostgreSQL that listens only on localhost, and
# N8N_LISTEN_ADDRESS and N8N_PORT decide where it listens.
module "podman" {
  source = "github.com/conn3xorg/circuit-podman?ref=v0.1.0"

  depends_on = [conn3x_command.n8n__key, conn3x_directory.n8n__data]

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  containers = {
    n8n = {
      image       = local.image
      volumes     = ["${local.data}:/home/node/.n8n:Z,U"]
      environment = local.environment
      extra       = ["Network=host", "EnvironmentFile=${local.keys_file}"]
    }
  }
  secrets = {
    n8n = merge(var.environment, var.postgres == null ? {} : { DB_POSTGRESDB_PASSWORD = var.postgres_password })
  }
}

circuit "ready" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # On a first start n8n pulls a large image and sets up its database
  # before it listens.
  step "port" {
    depends_on = [module.podman]
    wait_for {
      port    = var.port
      timeout = "15m"
    }
  }

  # Write-only: the plan and state record only an HMAC of the content.
  step "owner_password" {
    for_each = toset(var.owner == null ? [] : ["owner"])
    file {
      path       = "${local.etc}/owner_password"
      content_wo = var.owner_password
      owner      = "root"
      group      = "root"
      mode       = "0600"
    }
  }

  step "owner_script" {
    for_each = toset(var.owner == null ? [] : ["owner"])
    file {
      path    = "${local.etc}/owner-setup.mjs"
      content = local.owner_script
      owner   = "root"
      group   = "root"
      mode    = "0600"
    }
  }

  # Runs again only when the owner input changes, and then does nothing
  # once n8n has an owner: it creates the owner, never changes one.
  step "owner" {
    for_each = toset(var.owner == null ? [] : ["owner"])
    command {
      command  = "podman exec -i n8n node --input-type=module -e \"$(cat ${local.etc}/owner-setup.mjs)\" < ${local.etc}/owner_password"
      triggers = sha256(local.owner_script)
    }
  }
}
