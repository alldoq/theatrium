# Atrium

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Deploying to theatrium.online

The VPS is shared with other Phoenix apps (e.g. clarence.alldoq.com). Everything
atrium-related is isolated under `/home/user/atrium` and listens on port `4100`.

### One-time server setup

On the VPS, as the deploy user (see `bin/deploy_remote_production`):

```bash
# 1. Install OS packages (as root, once)
sudo apt update && sudo apt install -y git build-essential libssl-dev autoconf \
  libncurses-dev unzip postgresql nginx certbot python3-certbot-nginx

# 2. Install asdf + pinned versions
bin/deploy setup

# 3. Create Postgres role + DB
sudo -u postgres createuser -P atrium     # set a password
sudo -u postgres createdb -O atrium atrium_prod

# 4. Populate /home/user/atrium/shared/.env (see "Env vars" below)

# 5. Deploy from your workstation
bin/deploy_remote_production deploy

# 6. Install nginx config + request TLS cert
sudo cp /home/user/atrium/current/nginx/atrium.conf /etc/nginx/sites-available/theatrium.online.conf
sudo ln -sf /etc/nginx/sites-available/theatrium.online.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d theatrium.online
```

### Env vars

Create `/home/user/atrium/shared/.env` on the VPS:

```
DATABASE_URL=ecto://atrium:PASSWORD@localhost/atrium_prod
SECRET_KEY_BASE=<run: mix phx.gen.secret>
PHX_HOST=theatrium.online
PORT=4100
ATRIUM_CLOAK_KEY=<run: openssl rand -base64 32>
ATRIUM_FILE_ENCRYPTION_KEY=<run: openssl rand -base64 32>
ATRIUM_UPLOADS_ROOT=/home/user/atrium/shared/uploads
```

### Deploying

From your workstation:

```bash
bin/deploy_remote_production deploy      # ship main
bin/deploy_remote_production rollback    # revert to previous release
```

The `deploy` action: clones the repo, installs asdf versions, fetches deps,
compiles assets, builds a release, runs global + per-tenant migrations, rotates
the `current` symlink, restarts the daemon, cleans old releases.

