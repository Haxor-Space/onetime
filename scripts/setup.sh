#!/usr/bin/env bash
# setup.sh – interactive first-time setup for the Onetime Secret stack
#
# Usage:  bash scripts/setup.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
HTPASSWD_FILE="$REPO_ROOT/nginx/.htpasswd"

# ── Helpers ──────────────────────────────────────────────────────────────────

print_step() { echo; echo "▸ $*"; }
require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' is required but not installed." >&2
        exit 1
    fi
}

# ── Pre-flight checks ────────────────────────────────────────────────────────

require_cmd docker
require_cmd openssl

# ── .env ────────────────────────────────────────────────────────────────────

print_step "Setting up .env"
if [[ -f "$ENV_FILE" ]]; then
    echo "  .env already exists – skipping. Delete it and re-run to regenerate."
else
    SECRET_KEY="$(openssl rand -hex 32)"
    sed "s/change-this-to-a-long-random-value/$SECRET_KEY/" \
        "$REPO_ROOT/.env.example" > "$ENV_FILE"
    echo "  Created .env with a freshly generated SECRET_KEY."
fi

# ── nginx basic-auth credentials ────────────────────────────────────────────

print_step "Configuring nginx basic-auth credentials"
if [[ -f "$HTPASSWD_FILE" ]]; then
    echo "  .htpasswd already exists."
    read -r -p "  Add another user? [y/N] " ADD_USER
    ADD_USER="${ADD_USER:-n}"
else
    ADD_USER="y"
fi

if [[ "$ADD_USER" =~ ^[Yy]$ ]]; then
    read -r -p "  Username: " AUTH_USER
    if [[ -z "$AUTH_USER" ]]; then
        echo "  No username entered – skipping."
    else
        # Use docker to run htpasswd so we don't need apache2-utils installed
        if command -v htpasswd &>/dev/null; then
            if [[ -f "$HTPASSWD_FILE" ]]; then
                htpasswd -B "${HTPASSWD_FILE}" "$AUTH_USER"
            else
                htpasswd -cB "${HTPASSWD_FILE}" "$AUTH_USER"
            fi
        else
            ENTRY="$(docker run --rm -it httpd:alpine htpasswd -nB "$AUTH_USER")"
            echo "$ENTRY" >> "$HTPASSWD_FILE"
            echo "  Added user '$AUTH_USER' to .htpasswd."
        fi
    fi
fi

# ── Cloudflare tunnel token (optional) ──────────────────────────────────────

print_step "Cloudflare Tunnel (optional)"
echo "  If you have a Cloudflare Tunnel token, paste it here."
echo "  Leave blank to skip (you can still access the service on localhost)."
read -r -p "  Tunnel token: " CF_TOKEN

if [[ -n "$CF_TOKEN" ]]; then
    # Update the token in .env (replace the empty placeholder).
    # Use a temp file for cross-platform compatibility (BSD/macOS vs GNU sed).
    TMPFILE="$(mktemp)"
    sed "s|^CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=$CF_TOKEN|" "$ENV_FILE" > "$TMPFILE"
    mv "$TMPFILE" "$ENV_FILE"
    echo "  Token saved to .env."
fi

# ── Done ─────────────────────────────────────────────────────────────────────

print_step "Setup complete!"
echo
echo "  Start the stack (without cloudflared):"
echo "    docker compose up -d"
echo
if [[ -n "${CF_TOKEN:-}" ]]; then
    echo "  Start the stack (with cloudflared tunnel):"
    echo "    docker compose --profile cloudflare up -d"
    echo
fi
echo "  Access locally at: http://localhost:\$(grep NGINX_PORT $ENV_FILE | cut -d= -f2)"
