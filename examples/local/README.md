# Local example

Applies circuit-n8n to a throwaway Rocky Linux 10 container with systemd, with SQLite and an owner account. You need Conn3x and Podman.

n8n runs under Podman inside that container, so the host container is privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The first apply takes a few minutes: it installs Podman, pulls n8n's image, waits while n8n sets up its database, and creates the owner `owner@example.com`. The second plan says `No changes.` The owner's password is a default in `main.tf`, which you'd never keep on a real host.

If the pull stops with `toomanyrequests`, you've hit Docker Hub's limit for pulls without an account. Pull from GitHub's registry instead, which has the same image:

```sh
conn3x apply -var image_repository=ghcr.io/n8n-io/n8n
```

n8n listens on `127.0.0.1:5678` inside the container. To see the editor, forward that port over SSH, then open `http://localhost:5678` and sign in as `owner@example.com`:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts -L 5678:127.0.0.1:5678 root@127.0.0.1
```

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
