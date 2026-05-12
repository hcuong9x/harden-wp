# harden-wp

Modular WordPress hardening scripts for Webinoly, Tino Script, OpenLiteSpeed,
and custom WordPress paths.

The old single-file scripts are left at the repository root. This folder is the
new maintainable layout.

## Layout

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
  docs/features.md       Feature-to-module map and roadmap
  tests/run-tests.sh     Local smoke test with a fake WordPress tree
```

## Common commands

Webinoly:

```bash
sudo bash harden-wp/bin/harden-wp --mode harden --stack webinoly --domain example.com
```

Tino:

```bash
sudo bash harden-wp/bin/harden-wp --mode harden --stack tino --domain example.com
```

OpenLiteSpeed:

```bash
sudo bash harden-wp/bin/harden-wp --mode harden --stack ols --domain example.com
```

Custom path:

```bash
sudo bash harden-wp/bin/harden-wp --mode harden --stack custom --webroot /path/to/public_html
```

Unlock temporarily before updates:

```bash
sudo bash harden-wp/bin/harden-wp --mode unlock-update --stack custom --webroot /path/to/public_html
```

Scan only:

```bash
bash harden-wp/bin/harden-wp --mode scan --stack custom --webroot /path/to/public_html --yes --no-chown
```

Strict mode also sets `DISALLOW_FILE_MODS`, so WordPress admin cannot install or
update plugins/themes:

```bash
sudo bash harden-wp/bin/harden-wp --mode harden --stack custom --webroot /path/to/public_html --strict
```

## Safety model

Default harden mode:

- locks WordPress core, plugins, themes, and root code files
- keeps `uploads`, `cache`, `upgrade`, `litespeed`, and `ai1wm-backups`
  writable when they exist
- blocks PHP execution in writable runtime folders
- protects common sensitive files
- disables directory listing through webserver rules
- writes a permission snapshot before changing permissions when possible

Quarantine is intentionally not automatic yet. The scan mode reports suspicious
files first because malware signatures can have false positives in real plugins.
