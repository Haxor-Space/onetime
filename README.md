# Onetime Secret – self-hosted stack

A self-hostable [One-Time Secret](https://github.com/onetimesecret/onetimesecret) instance, protected by nginx HTTP basic auth and optionally exposed via a [Cloudflare Tunnel](https://www.cloudflare.com/products/tunnel/).

## Services

| Service | Description |
|---|---|
| **redis** | Persistence backend for secrets |
| **onetimesecret** | The secret-sharing application |
| **nginx** | Reverse proxy with HTTP basic auth |
| **cloudflared** | Cloudflare Tunnel connector *(optional – enabled with the `cloudflare` profile)* |

## Quick start

### 1 – Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with the Compose plugin
- `openssl` (used by the setup script to generate a secret key)

### 2 – Clone and run setup

```bash
git clone https://github.com/Haxor-Space/onetime.git
cd onetime
bash scripts/setup.sh
```

The setup script will:
1. Generate a `.env` file with a random `SECRET_KEY`
2. Create a `nginx/.htpasswd` credentials file (add as many users as you like)
3. Optionally store your Cloudflare Tunnel token

### 3 – Start the stack

**Without Cloudflare (local / port-forward only):**
```bash
docker compose up -d
```

**With Cloudflare Tunnel:**
```bash
docker compose --profile cloudflare up -d
```

The service is then available at `http://localhost:8080` (or whichever `NGINX_PORT` you configured), protected by the credentials you created.

---

## Manual setup (without the script)

### a) Create `.env`

```bash
cp .env.example .env
```

Edit `.env` and fill in:

| Variable | Description |
|---|---|
| `SECRET_KEY` | Long random string – generate with `openssl rand -hex 32` |
| `NGINX_PORT` | Local port nginx listens on (default `8080`) |
| `CLOUDFLARE_TUNNEL_TOKEN` | Tunnel token from the Cloudflare dashboard (leave empty if not using) |

### b) Create nginx credentials

Add one or more users to `nginx/.htpasswd`. The file must exist even if it is empty.

Using `htpasswd` from `apache2-utils`:
```bash
# First user (creates the file)
htpasswd -cB nginx/.htpasswd alice
# Additional users
htpasswd -B nginx/.htpasswd bob
```

Using Docker (no extra tools needed):
```bash
docker run --rm -it httpd:alpine htpasswd -nB alice >> nginx/.htpasswd
```

### c) Start

```bash
docker compose up -d                              # local only
docker compose --profile cloudflare up -d         # with cloudflared
```

---

## Cloudflare Tunnel setup

1. Log in to the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/).
2. Navigate to **Networks → Tunnels → Create a tunnel**.
3. Choose **Cloudflared** as the connector type and give the tunnel a name.
4. When prompted, copy the **tunnel token**.
5. Under **Public Hostname**, add a hostname pointing to `http://nginx:80`.
6. Paste the token into your `.env`:
   ```
   CLOUDFLARE_TUNNEL_TOKEN=<your-token-here>
   ```
7. Start the stack with the `cloudflare` profile:
   ```bash
   docker compose --profile cloudflare up -d
   ```

> **Tip:** You can add an additional layer of authentication with [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/policies/access/) on top of the nginx basic auth.

---

## Managing users

Add a user:
```bash
htpasswd -B nginx/.htpasswd <username>
```

Remove a user:
```bash
htpasswd -D nginx/.htpasswd <username>
```

After modifying `.htpasswd`, reload nginx:
```bash
docker compose exec nginx nginx -s reload
```

---

## Upgrading

```bash
docker compose pull
docker compose up -d
```

---

## Data persistence

Redis data is stored in the `redis_data` Docker volume. Docker Compose prefixes volumes with the project name (the directory name by default), so the full volume name will be something like `onetime_redis_data`. Confirm with `docker volume ls`.

To back it up:
```bash
VOLUME="$(docker compose config --volumes | grep redis | head -1)"
docker run --rm \
    -v "${PWD##*/}_${VOLUME}:/data" \
    -v "$(pwd):/backup" \
    alpine tar czf /backup/redis-backup.tar.gz /data
```

---

## Security notes

- Change `SECRET_KEY` to a unique random value before first use – this key encrypts stored secrets.
- Do **not** expose the Redis port; it is intentionally kept internal to the compose network.
- The `nginx/.htpasswd` file should never be committed to version control – it is listed in `.gitignore`.
- The `.env` file should never be committed to version control – it is listed in `.gitignore`.
