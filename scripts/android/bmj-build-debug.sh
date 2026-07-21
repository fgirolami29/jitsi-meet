#!/usr/bin/env bash

CODECORN_ENV="${1:-lab}"
CUSTOM_EXIT_URL="${2:-}"

LAB_URL='https://live.barbagiamusei.test/musei-in-diretta?bmj_totem=1'
PRODUCTION_URL='https://live.barbagiamusei.it/musei-in-diretta?bmj_totem=1'

JAVA_HOME="$(
  /usr/libexec/java_home -v 11
)"
PATH="$JAVA_HOME/bin:$PATH"

ADB="$HOME/Library/Android/sdk/platform-tools/adb"

case "$CODECORN_ENV" in
  lab)
    DEFAULT_URL="$LAB_URL"
    ;;
  production|prod)
    DEFAULT_URL="$PRODUCTION_URL"
    ;;
  *)
    printf 'Ambiente non valido: %s\n' "$CODECORN_ENV"
    printf 'Valori ammessi: lab, production, prod\n'
    return 1 2>/dev/null || false
    ;;
esac

BMJ_EXIT_URL="${CUSTOM_EXIT_URL:-$DEFAULT_URL}"

load_env_paths() {
  local repo_root

  repo_root="$(
    git rev-parse --show-toplevel 2>/dev/null
  )"

  if [[ -z "$repo_root" || ! -d "$repo_root/android" ]]; then
    printf 'Root repository Android non trovata.\n'
    return 1
  fi

  export JAVA_HOME
  export PATH
  export BMJ_EXIT_URL

  cd "$repo_root/android" || {
    printf 'Directory Android inesistente: %s/android\n' "$repo_root"
    return 1
  }
}

stop_gradle_and_build() {
  printf '\n===== BUILD CONFIG =====\n'
  printf 'CODECORN_ENV=%s\n' "$CODECORN_ENV"
  printf 'BMJ_EXIT_URL=%s\n' "$BMJ_EXIT_URL"
  printf 'JAVA_HOME=%s\n' "$JAVA_HOME"

  printf '\n===== JAVA =====\n'
  java -version

  printf '\n===== GRADLE STOP =====\n'
  ./gradlew --stop

  printf '\n===== ASSEMBLE DEBUG =====\n'
  BMJ_EXIT_URL="$BMJ_EXIT_URL" \
    ./gradlew \
      --no-daemon \
      --stacktrace \
      assembleDebug
}

find_debug_apk() {
  find app/build/outputs/apk \
    -type f \
    -name '*debug*.apk' \
    -print \
    | sort \
    | tail -n 1
}

install_debug_apk() {
  local apk

  apk="$(find_debug_apk)"

  if [[ -z "$apk" || ! -f "$apk" ]]; then
    printf 'APK debug non trovato.\n'
    return 1
  fi

  if [[ ! -x "$ADB" ]]; then
    printf 'ADB non trovato o non eseguibile: %s\n' "$ADB"
    return 1
  fi

  printf '\n===== APK =====\n'
  printf '%s\n' "$apk"

  printf '\n===== DEVICES =====\n'
  "$ADB" devices

  printf '\n===== INSTALL =====\n'
  "$ADB" install -r "$apk"
}

build_up() {
  load_env_paths || return 1
  stop_gradle_and_build || return 1
  install_debug_apk || return 1

  printf '\n===== COMPLETATO =====\n'
  printf 'Ambiente: %s\n' "$CODECORN_ENV"
  printf 'Exit URL: %s\n' "$BMJ_EXIT_URL"
}

build_up
