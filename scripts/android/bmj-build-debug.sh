#!/usr/bin/env bash
EMULATOR='emulator-5554'

usage() {
  cat <<'EOF'
Uso:
  scripts/android/bmj-build-debug.sh [ambiente] [exit-url] [server-url]

Ambienti:
  lab                usa live.barbagiamusei.test
  production | prod  usa live.barbagiamusei.it

Esempi:

  # LAB
  scripts/android/bmj-build-debug.sh

  # PRODUZIONE
  scripts/android/bmj-build-debug.sh production

  # URL personalizzato
  scripts/android/bmj-build-debug.sh lab \
    'https://example.test/musei-in-diretta?bmj_totem=1'
EOF
}

if [[ ${1:-} == '-h' || ${1:-} == '--help' ]]; then
  usage
  exit 0
fi

CODECORN_ENV="${1:-lab}"

LAB_SERVER_URL='https://live.barbagiamusei.test/'
LAB_EXIT_URL='https://live.barbagiamusei.test/musei-in-diretta?bmj_totem=1'

PRODUCTION_SERVER_URL='https://live.barbagiamusei.it/'
PRODUCTION_EXIT_URL='https://live.barbagiamusei.it/musei-in-diretta?bmj_totem=1'

BMJ_APP_LINK_PATH='/app/musei-in-diretta'
BMJ_CONFERENCE_PATH='/musei-in-diretta'

case "$CODECORN_ENV" in
lab)
  DEFAULT_SERVER_URL="$LAB_SERVER_URL"
  DEFAULT_EXIT_URL="$LAB_EXIT_URL"
  GRADLE_TASK='assembleLabRelease'
  APK_DIR='app/build/outputs/apk/labRelease'
  ;;
production | prod)
  DEFAULT_SERVER_URL="$PRODUCTION_SERVER_URL"
  DEFAULT_EXIT_URL="$PRODUCTION_EXIT_URL"
  GRADLE_TASK='assembleRelease'
  APK_DIR='app/build/outputs/apk/release'
  ;;
*)
  printf 'Ambiente non valido: %s\n' "$CODECORN_ENV"
  usage
  exit 2
  ;;
esac

JAVA_HOME="$(
  /usr/libexec/java_home -v 11
)"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_SDK_ROOT/platform-tools/adb"

PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

BMJ_EXIT_URL="${2:-$DEFAULT_EXIT_URL}"
BMJ_SERVER_URL="${3:-$DEFAULT_SERVER_URL}"

if [[ -n ${2:-} && -z ${3:-} ]]; then
  BMJ_SERVER_URL="$(
    python3 - "$BMJ_EXIT_URL" <<'PYURL'
import sys
from urllib.parse import urlsplit

parsed = urlsplit(sys.argv[1])

if parsed.scheme != "https" or not parsed.hostname:
    raise SystemExit("Exit URL personalizzato non valido")

authority = parsed.hostname

if parsed.port:
    authority = f"{authority}:{parsed.port}"

print(f"https://{authority}")
PYURL
  )" || {
    printf 'ERRORE: impossibile derivare BMJ_SERVER_URL da %s\n' "$BMJ_EXIT_URL"
    exit 2
  }
fi

load_env_paths() {
  local repo_root

  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"

  if [[ -z "$repo_root" || ! -d "$repo_root/android" ]]; then
    printf 'Repository Android non trovata.\n'
    return 1
  fi

  unset NODE_OPTIONS

  export JAVA_HOME
  export ANDROID_SDK_ROOT
  export PATH
  export BMJ_SERVER_URL
  export BMJ_EXIT_URL
  export BMJ_APP_LINK_PATH
  export BMJ_CONFERENCE_PATH

  cd "$repo_root/android" || {
    printf 'Directory Android inesistente: %s/android\n' "$repo_root"
    return 1
  }
}
stop_gradle_and_build() {
  printf '\n===== CONFIGURAZIONE =====\n'
  printf 'Ambiente: %s\n' "$CODECORN_ENV"
  printf 'Server URL: %s\n' "$BMJ_SERVER_URL"
  printf 'Exit URL: %s\n' "$BMJ_EXIT_URL"
  printf 'App Link path: %s\n' "$BMJ_APP_LINK_PATH"
  printf 'Conference path: %s\n' "$BMJ_CONFERENCE_PATH"
  printf 'Java: %s\n' "$JAVA_HOME"
  printf 'ADB: %s\n' "$ADB"
  printf 'Gradle task: %s\n' "$GRADLE_TASK"
  printf 'APK dir: %s\n' "$APK_DIR"

  printf '\n===== GRADLE STOP =====\n'
  ./gradlew --stop

  printf '\n===== BUILD ANDROID =====\n'
  BMJ_SERVER_URL="$BMJ_SERVER_URL" \
    BMJ_EXIT_URL="$BMJ_EXIT_URL" \
    BMJ_APP_LINK_PATH="$BMJ_APP_LINK_PATH" \
    BMJ_CONFERENCE_PATH="$BMJ_CONFERENCE_PATH" \
    ./gradlew \
    --no-daemon \
    --stacktrace \
    "$GRADLE_TASK"
}

find_and_install() {
  local apk

  apk="$(
    find "$APK_DIR" \
      -type f \
      -name '*.apk' \
      -print \
      | sort \
      | tail -n 1
  )"

  if [[ -z "$apk" || ! -f "$apk" ]]; then
    printf 'APK non trovato sotto: %s\n' "$APK_DIR"
    return 1
  fi

  printf '\n===== APK =====\n'
  printf '%s\n' "$apk"

  printf '\n===== DEVICES =====\n'
  "$ADB" devices

  printf '\n===== INSTALL =====\n'
  "$ADB" -s "$EMULATOR" install -r "$apk"
}

check_node_runtime() {
  local node_major

  node_major="$(
    node -p 'process.versions.node.split(".")[0]'
  )"

  printf '\n===== NODE =====\n'
  printf 'Binario: %s\n' "$(command -v node)"
  printf 'Versione: %s\n' "$(node --version)"

  if [[ "$node_major" != '16' ]]; then
    printf 'Questo ramo richiede Node 16; versione attiva: %s\n' "$(node --version)"
    return 1
  fi
}

build_up() {
  load_env_paths || return 1
  check_node_runtime || return 1
  stop_gradle_and_build || return 1
  find_and_install || return 1

  printf '\n===== DEPLOY COMPLETATO =====\n'
  printf 'Ambiente: %s\n' "$CODECORN_ENV"
  printf 'Server URL: %s\n' "$BMJ_SERVER_URL"
  printf 'Exit URL: %s\n' "$BMJ_EXIT_URL"
}

build_up
