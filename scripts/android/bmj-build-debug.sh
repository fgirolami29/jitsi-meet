#!/usr/bin/env bash

usage() {
  cat <<'EOF'
#!/usr/bin/env bash

# LAB
scripts/android/bmj-build-debug.sh

# PRODUZIONE
scripts/android/bmj-build-debug.sh production

# URL personalizzato
scripts/android/bmj-build-debug.sh lab \
  'https://example.test/musei-in-diretta?bmj_totem=1'
EOF
}

[[ ${1:-} == '-h' || ${1:-} == '--help' ]] && {
  usage
  return 0 2>/dev/null
}

CODECORN_ENV=${1:-'lab'}
DEFAULT_URL='https://live.barbagiamusei.it/musei-in-diretta?bmj_totem=1'
[[ $CODECORN_ENV == 'lab' ]] && DEFAULT_URL='https://live.barbagiamusei.test/musei-in-diretta?bmj_totem=1'
# Build debug
JAVA_HOME=$(/usr/libexec/java_home -v 11)
PATH="$JAVA_HOME/bin:$PATH"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
BMJ_EXIT_URL=${2:-$DEFAULT_URL}

load_env_paths() {

  export JAVA_HOME \
    PATH

  cd "$(git rev-parse --show-toplevel)/android" || echo "path Inesistente di lancio" && return 1
}

kill_gradlew_and_build() {
  ./gradlew --stop

  "$BMJ_EXIT_URL" \
    ./gradlew \
    --no-daemon \
    --stacktrace \
    assembleDebug
}

# Trova e installa APK
find_and_install() {
  cd "$(git rev-parse --show-toplevel)/android" || echo "find_and_install path Inesistente di lancio" && return 1
  APK="$(
    find android/app/build/outputs/apk \
      -type f \
      -name '*debug*.apk' \
      | head -n 1
  )"

  printf 'APK=%s\n' "$APK"

  "$ADB" devices
  "$ADB" install -r "$APK"
}

build_UP() {

  load_env_paths
  kill_gradlew_and_build

  find_and_install
  exit 0
}

build_UP "$@"
