# harden-wp

Modular WordPress hardening scripts for Webinoly, Tino Script, OpenLiteSpeed,
and custom WordPress paths.

## What this script does

- hardens file ownership and permissions for WordPress code
- keeps runtime write paths writable (`uploads`, optional cache-like folders)
- writes defensive `.htaccess` rules and optional Webinoly nginx rules
- hardens `wp-config.php` constants and file mode
- supports permission snapshot and restore
- supports lightweight malware-oriented scan
- supports immutable flag mode (`chattr +i` / `-i`)
- supports sha256 integrity baseline and verification

## Project layout

```text
harden-wp/
  bin/harden-wp          Main command
  lib/common.sh          Logging, command wrapper, marker block helper
  lib/paths.sh           Stack path resolution and owner detection
  lib/permissions.sh     chmod/chown harden and unlock logic
  lib/webserver.sh       .htaccess and Webinoly nginx rules
  lib/wp_config.sh       DISALLOW_FILE_EDIT / optional DISALLOW_FILE_MODS
  lib/scan.sh            Malware-oriented reporting
  lib/snapshot.sh        getfacl snapshot and restore
  lib/immutable.sh       chattr +i / -i
  lib/integrity.sh       sha256 baseline and verify
  tests/run-tests.sh     Local smoke test with a fake WordPress tree
```

## Usage

If you are inside this repository directory:

```bash
bash bin/harden-wp --help
```

If you are in the parent directory:

```bash
bash harden-wp/bin/harden-wp --help
```

Use `sudo` for modes that change permissions, ownership, or file attributes.

## Stack mapping

| Stack | Default WEBROOT | Default WP_CONFIG |
| --- | --- | --- |
| `webinoly` | `/var/www/<domain>/htdocs` | `/var/www/<domain>/wp-config.php` |
| `tino` | `/home/<domain>/public_html` | `<webroot>/wp-config.php` |
| `ols` | `/home/www/<domain>/public_html` | `<webroot>/wp-config.php` |
| `custom` | must pass `--webroot` | default `<webroot>/wp-config.php`, or pass `--config` |

Domain validation rejects path-like or malformed values such as `..`, `/`, `\`,
or unsupported characters.

## Modes

| Mode | Purpose |
| --- | --- |
| `harden` | Lock code paths, update wp-config constants, write webserver rules |
| `unlock-update` | Reset base permissions for updates, including `wp-config.php` |
| `scan` | Report suspicious files/patterns (read-only scan) |
| `snapshot` | Save permissions snapshot (`getfacl`, or stat-only fallback) |
| `restore-permission` | Restore permissions from a `getfacl` snapshot |
| `immutable` | Apply `chattr +i` to selected critical files |
| `unimmutable` | Remove immutable flag (`chattr -i`) |
| `baseline` | Generate sha256 baseline file |
| `verify-integrity` | Verify files against a baseline |

## Common commands

Harden (Webinoly):

```bash
sudo bash bin/harden-wp --mode harden --stack webinoly --domain example.com
```

Harden (custom path):

```bash
sudo bash bin/harden-wp --mode harden --stack custom --webroot /path/to/public_html
```

Temporarily unlock for updates:

```bash
sudo bash bin/harden-wp --mode unlock-update --stack webinoly --domain example.com
```

Scan only (no ownership changes):

```bash
bash bin/harden-wp --mode scan --stack custom --webroot /path/to/public_html --yes --no-chown
```

Create snapshot explicitly:

```bash
sudo bash bin/harden-wp --mode snapshot --stack webinoly --domain example.com
```

Restore from snapshot:

```bash
sudo bash bin/harden-wp --mode restore-permission --stack webinoly --domain example.com --snapshot /var/www/example.com/.harden-wp/snapshots/permissions-htdocs-YYYYmmdd-HHMMSS.acl
```

Generate and verify integrity baseline:

```bash
sudo bash bin/harden-wp --mode baseline --stack webinoly --domain example.com
sudo bash bin/harden-wp --mode verify-integrity --stack webinoly --domain example.com --baseline /var/www/example.com/.harden-wp/baselines/baseline-htdocs-YYYYmmdd-HHMMSS.sha256
```

Enable strict wp-config hardening (`DISALLOW_FILE_MODS` too):

```bash
sudo bash bin/harden-wp --mode harden --stack webinoly --domain example.com --strict
```

Dry run:

```bash
sudo bash bin/harden-wp --mode harden --stack webinoly --domain example.com --dry-run
```

## Key options

| Option | Description |
| --- | --- |
| `--mode` | Required operation mode |
| `--stack` (`--type`) | `webinoly`, `tino`, `ols`, `custom` |
| `--domain` | Domain used to build default paths for non-custom stacks |
| `--webroot` | Override WordPress webroot |
| `--config` | Override `wp-config.php` path |
| `--owner USER:GROUP` | Force ownership target instead of auto-detect |
| `--snapshot FILE` | Snapshot path for `snapshot` / `restore-permission` |
| `--baseline FILE` | Baseline path for `baseline` / `verify-integrity` |
| `--strict` | Also set `DISALLOW_FILE_MODS` |
| `--yes` | Continue when WordPress markers are missing |
| `--dry-run` | Print commands without applying changes |
| `--no-chown` | Skip ownership changes |
| `--no-snapshot` | Skip automatic snapshot in `harden` mode |
| `--no-nginx-reload` | Do not run `nginx -t` and reload after Webinoly rule write |

## Harden behavior in detail

`harden` mode performs:

- `chown -R <owner> <webroot>` unless `--no-chown`
- base permissions: directories `755`, files `644`
- lock code trees:
  - `wp-admin`, `wp-includes`, `wp-content/themes`, `wp-content/plugins`
    to directories `555`, files `444`
- lock root code files in webroot to `444`
- lock top-level `webroot` and `wp-content` to `555`
- keep runtime writable paths at `755/644`:
  - always `wp-content/uploads`
  - optional if present: `cache`, `litespeed`, `upgrade`, `ai1wm-backups`
- set `wp-config.php` to `400` (fallback `440` if needed)
- insert/update hardening marker blocks:
  - root `.htaccess`
  - runtime `.htaccess` blocks to deny PHP execution in writable dirs
  - Webinoly nginx rule file `/var/www/<domain>/nginx/harden-wp.conf`

## Safety and recovery

Recommended workflow:

1. Run `--dry-run` first on production.
2. Run `harden`.
3. If updates are needed, run `unlock-update`, perform updates, then run `harden` again.

If site breaks right after harden:

1. Unlock first:

```bash
sudo bash bin/harden-wp --mode unlock-update --stack webinoly --domain example.com
```

2. If still broken, restore from snapshot:

```bash
sudo ls -lt /var/www/example.com/.harden-wp/snapshots
sudo bash bin/harden-wp --mode restore-permission --stack webinoly --domain example.com --snapshot /var/www/example.com/.harden-wp/snapshots/<snapshot-file>.acl
```

3. For Webinoly, avoid owner mismatch by setting explicit owner when needed:

```bash
sudo bash bin/harden-wp --mode harden --stack webinoly --domain example.com --owner www-data:www-data
```

## Notes and limitations

- `restore-permission` requires a real `getfacl` snapshot and `setfacl`.
- if `getfacl` is missing, fallback snapshot is stat-only and cannot auto-restore
- scan mode reports findings only; it does not auto-quarantine
- immutable mode requires root and filesystem support for `chattr`
- on `webinoly`, if auto-detected owner is `root:root`, script falls back to
  `www-data:www-data` unless `--owner` is explicitly provided

## Local test

Run local smoke test:

```bash
bash tests/run-tests.sh
```
