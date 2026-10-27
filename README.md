# Luanti HACKED server

Server-side code and cloud deployment for the Mineclonia automation server.
Every authenticated join receives a new restricted-DSL challenge, with a
four-second deadline and exactly one submitted answer. Incorrect answers or
expiry kick the player; reconnecting immediately issues a new puzzle. The
minimum number of steps is semantic: redundant/cancelling operations do not
make a solution complex enough.

This repository does not include a client helper or solver. The server sends
public challenge examples and protocol bounds only, never client-mod code or
hidden validation tests. Players bring their own tools or use the manual form.
Normal Luanti authentication still establishes account identity. This gate is
after authentication and does not prove AI/LLM use. Removing interact is not a
complete quarantine against every Mineclonia action.

## Cloud setup

Requirements: Git, Python 3, Docker Engine and the Docker Compose plugin.
Use a regular host user that can run Docker. The setup generates matching
container UID/GID values so its persistent files remain owned by that user.

```sh
git clone YOUR_REPOSITORY_URL luanti-hacked-server
cd luanti-hacked-server
python3 scripts/setup.py
```

The setup fetches Mineclonia at the revision in `mineclonia.lock.json`, creates
persistent directories, copies the example config if none exists, and prepares
a fresh world with SQLite map/player/auth/mod-storage backends. It leaves
existing configuration, account data and backend choices intact. An existing
Mineclonia checkout at a different revision is reported rather than reset.

Edit the generated `.env`: for remote clients set `PUBLISH_ADDRESS=0.0.0.0`.
The default publishes only on host loopback. Allow inbound **UDP 30000** in the
cloud firewall/security group (or the `SERVER_PORT` you choose). Engine binding
inside the container is separate and uses 0.0.0.0. Ordinary HTTP hosting cannot
run this UDP server; use a VM/container host supporting persistent storage.

Review `config/minetest.conf`, then start:

```sh
docker compose up -d
docker compose logs -f server
```

Look for `[ai_gate] loaded (4s deadline, minimum 2 steps)` and the listener line.
Connect a normal Luanti client to the host address and UDP port. Test accounts
must solve a fresh puzzle on each join. The local client toolkit lives outside
this server repository and is not automatically downloaded.

## Persistent data and updates

`runtime/` contains the world, accounts, inventories, mod storage and caches.
`config/` and `.env` contain deployment-specific settings. `games/` is fetched
upstream content. All are ignored by Git, as are databases/logs/backups; only
source, a sanitized example and deployment instructions belong in this repo.

Before importing an existing world, stop both servers and make a backup. Copy
the world into `runtime/.minetest/worlds/hacked/`, preserve its backend settings,
then rerun setup. The repository's ai_gate is mounted directly over the world's
mod path inside the container, so imported old mod files do not override the
version in Git. The underlying host files are not deleted by that mount.
Use Luanti's migration commands separately if importing a file-backend world;
changing a backend setting alone does not transfer player/account data.

Back up `runtime/` and `config/` with the server stopped. Updating code is:

```sh
docker compose stop server
git pull --ff-only
python3 scripts/setup.py
docker compose up -d
```

The image is version-pinned to Luanti 5.17.0; inspect upstream release changes
before changing it. Mineclonia is fetched separately and retains its upstream
license. This repository does not vendor or modify upstream Mineclonia.
No license for this project's own source has been selected yet.

## Tests

```sh
luajit tests/ai_gate_test.lua
luajit tests/complexity_test.lua
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/audit.py
docker compose config --quiet
```

Lua tests also run with `lua`/`lua5.4`. The test workflow runs them on pushes and
pull requests. They simulate engine callbacks/JSON/channels; they do not replace
a live Mineclonia join. Local preparation passed the LuaJIT/Lua suites and setup
tests. Image pull, game fetch, container startup and actual cloud networking
have not been tested in the restricted preparation environment. Docker Compose
is not installed in that environment, so its validation is configured in CI
rather than claimed as a local result.

Deployment follows the official [container documentation](https://docs.luanti.org/for-server-hosts/setup/containers/)
and the [5.17 image definition](https://github.com/luanti-org/luanti/blob/5.17.0/Dockerfile).

## Development workspace

In the combined private client/server workspace, the installed ai_gate mod is
the working source. Run `python3 tools/sync_server.py` from that workspace before
committing in this repository; it refreshes only an explicit allowlist of server
mod/test files. Deployment files here are edited directly. Do not copy the
workspace root, its live minetest.conf, world data, client code or solver into
this repository. `scripts/audit.py` checks the tracked-path allowlist before
publication/CI.
