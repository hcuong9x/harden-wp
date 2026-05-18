# Feature Map

This file maps the original proposal into maintainable modules.

## Implemented

| Feature | Module | Notes |
| --- | --- | --- |
| Stack path detection | `lib/paths.sh` | Webinoly, Tino, OpenLiteSpeed, custom |
| Owner detection | `lib/paths.sh` | Detects from real WordPress files, supports `--owner` |
| Permission harden | `lib/permissions.sh` | Core/plugins/themes/root code readonly |
| Writable whitelist | `lib/permissions.sh` | uploads always, cache/upgrade/litespeed/ai1wm when present |
| Update unlock mode | `lib/permissions.sh` | `--mode unlock-update` |
| PHP execution block | `lib/webserver.sh` | Runtime `.htaccess` and Webinoly nginx rules |
| Sensitive file block | `lib/webserver.sh` | `.env`, `.git`, composer files, logs, readme/license |
| XML-RPC block | `lib/webserver.sh` | Webserver-level deny |
| Directory listing off | `lib/webserver.sh` | `.htaccess` and nginx `autoindex off` |
| wp-config harden | `lib/wp_config.sh` | `DISALLOW_FILE_EDIT`; `DISALLOW_FILE_MODS` with `--strict` |
| Permission snapshot | `lib/snapshot.sh` | Uses `getfacl` when available |
| Permission restore | `lib/snapshot.sh` | Uses `setfacl --restore` |
| Malware scan report | `lib/scan.sh` | PHP in runtime dirs, suspicious PHP patterns, recent files |
| Symlink scan | `lib/scan.sh` | Reports symlinks |
| Immutable mode | `lib/immutable.sh` | `chattr +i` / `-i` for critical files |
| Integrity baseline | `lib/integrity.sh` | `sha256sum` baseline and verify |
| Fleet runner | `lib/fleet.sh`, `bin/fleet.sh` | Runs supported modes across all detected domains or declared webroots |
| Local smoke test | `tests/run-tests.sh` | Builds a fake WordPress tree in `/tmp` |

## Intentionally Manual For Now

| Feature | Reason |
| --- | --- |
| Auto quarantine | High false-positive risk; scan reports first |
| Disable vhost on malware | Needs stack-specific integration and operator confirmation |
| Move `wp-config.php` outside webroot | Safe only when stack layout is known |
| Multi-site user isolation | Server provisioning concern: Unix user, php-fpm pool, open_basedir |

## Suggested Next Modules

| Module | Purpose |
| --- | --- |
| `lib/quarantine.sh` | Move confirmed malware to quarantine with restore metadata |
| `lib/vhost.sh` | Stack-specific disable/enable site actions |
| `tests/fixtures/` | More realistic fake WordPress layouts for each stack |
