#!/usr/bin/env cc-md

Sì: **per compilare, installare e lanciare nel laboratorio usiamo il comando già canonico**:

```bash
npm run deploy:android:lab
```

Niente seconda pipeline parallela.

Appendiamo tutte le declinazioni esposte realmente da `gvm`, più `gmic`, e un comando unico per avviare la VM e fare il deploy.

## Patch `package.json`

```bash
#!/usr/bin/env bash

main() {
    local ROOT
    local PACKAGE
    local TMP
    local BACKUP
    local STAMP

    ROOT="$(
        git rev-parse --show-toplevel 2>/dev/null
    )"

    if [ -z "$ROOT" ]; then
        printf 'ERRORE: repository Git non rilevata.\n'
        return 1
    fi

    PACKAGE="$ROOT/package.json"
    STAMP="$(date '+%Y%m%d-%H%M%S')"
    BACKUP="$ROOT/_BACKUP/package-json/package.json.$STAMP"
    TMP="$(mktemp "${TMPDIR:-/tmp}/bmj-package.XXXXXX")"

    if [ ! -f "$PACKAGE" ]; then
        printf 'ERRORE: package.json non trovato: %s\n' "$PACKAGE"
        return 1
    fi

    mkdir -p "$(dirname "$BACKUP")" || return 1
    cp -p "$PACKAGE" "$BACKUP" || return 1

    PACKAGE_PATH="$PACKAGE" \
    OUTPUT_PATH="$TMP" \
    node <<'NODE'
const fs = require('fs');

const packagePath = process.env.PACKAGE_PATH;
const outputPath = process.env.OUTPUT_PATH;
const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8'));

pkg.scripts ??= {};

const vmScripts = {
    'vm:start': 'gvm start',
    'vm:stop': 'gvm stop',
    'vm:restart': 'gvm restart',
    'vm:status': 'gvm status',
    'vm:open': 'gvm open',
    'vm:logs': 'gvm logs',

    'vm:mic:on': 'gmic on',
    'vm:mic:off': 'gmic off',
    'vm:mic:toggle': 'gmic toggle',
    'vm:mic:status': 'gmic status',
    'vm:mic:apply': 'gmic apply --no-restart',

    'deploy:android:lab:boot': 'npm run vm:start && npm run deploy:android:lab'
};

pkg.scripts = {
    ...pkg.scripts,
    ...vmScripts
};

fs.writeFileSync(
    outputPath,
    `${JSON.stringify(pkg, null, 2)}\n`,
    'utf8'
);
NODE

    if ! node --check "$TMP" >/dev/null 2>&1; then
        # node --check non valida JSON: usiamo il parser corretto sotto.
        :
    fi

    if ! node -e \
        'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
        "$TMP"
    then
        printf 'ERRORE: JSON generato non valido.\n'
        rm -f "$TMP"
        return 1
    fi

    printf '\n===== DRY-RUN PACKAGE.JSON =====\n'

    diff -u \
        "$PACKAGE" \
        "$TMP" \
        || true

    printf '\nBackup: %s\n' "$BACKUP"
    printf '\nPremi INVIO per applicare, CTRL+C per annullare.\n'
    read -r

    mv "$TMP" "$PACKAGE" || return 1

    printf '\n===== VERIFICA JSON =====\n'

    node -e \
        'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log("package.json: OK")' \
        "$PACKAGE" \
        || return 1

    printf '\n===== SCRIPT VM REGISTRATI =====\n'

    npm pkg get scripts |
        grep -E \
            '"vm:|"deploy:android:lab' \
        || true

    printf '\n===== GIT DIFF CHECK =====\n'

    git diff --check -- package.json || return 1
    git diff -- package.json

    printf '\n===== TEST NON DISTRUTTIVO =====\n'

    npm run vm:status

    printf '\nPatch completata.\n'
    printf 'Backup: %s\n' "$BACKUP"
}

main "$@"
```

Il blocco finale degli script sarà:

```json
{
  "vm:start": "gvm start",
  "vm:stop": "gvm stop",
  "vm:restart": "gvm restart",
  "vm:status": "gvm status",
  "vm:open": "gvm open",
  "vm:logs": "gvm logs",
  "vm:mic:on": "gmic on",
  "vm:mic:off": "gmic off",
  "vm:mic:toggle": "gmic toggle",
  "vm:mic:status": "gmic status",
  "vm:mic:apply": "gmic apply --no-restart",
  "deploy:android:lab": "./scripts/android/bmj-build-debug.sh lab",
  "deploy:android:prod": "./scripts/android/bmj-build-debug.sh prod",
  "deploy:android:lab:boot": "npm run vm:start && npm run deploy:android:lab"
}
```

Uso quotidiano:

```bash
npm run vm:status
npm run vm:start
npm run vm:open
npm run vm:mic:off
npm run deploy:android:lab
```

Oppure, da VM spenta:

```bash
npm run deploy:android:lab:boot
```

Nota concreta: questo presuppone che `gvm` e `gmic` siano **comandi realmente disponibili nel `PATH`**, non semplici alias interattivi di zsh. Il `npm run vm:status` finale lo comprova immediatamente.
