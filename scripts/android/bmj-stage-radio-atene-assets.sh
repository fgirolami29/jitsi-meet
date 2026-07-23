#!/usr/bin/env bash

main() {
    local ROOT
    local BRAND
    local SOURCE
    local RES
    local STAMP
    local WORK
    local OUT
    local PREVIEW
    local MASTER
    local BG
    local SPEC
    local DENSITY
    local LEGACY
    local FOREGROUND
    local NOTIFICATION
    local INNER
    local FOREGROUND_INNER
    local NOTIFICATION_INNER
    local MARGIN
    local RADIUS
    local CENTER
    local MASK
    local FILE

    ROOT="$HOME/CodeCorn/Repositories/BARBAGIA/jitsi-meet-22.1.1-rebrand"
    BRAND="/Users/federicogirolami/Documents/PROMENTE/BARBAGIA MUSEI JITSI/branding/barbagiamusei"
    SOURCE="$BRAND/input/favicon.svg"
    RES="$ROOT/android/app/src/main/res"

    BG="#101718"

    STAMP="$(date '+%Y%m%d-%H%M%S')"
    WORK="$BRAND/_ANDROID_CASE/$STAMP-radio-atene-assets-stage"
    OUT="$WORK/android/app/src/main/res"
    PREVIEW="$WORK/preview"
    MASTER="$WORK/radio-atene-master.png"

    if ! command -v magick >/dev/null 2>&1; then
        printf 'ERRORE: ImageMagick / magick non trovato.\n'
        return 1
    fi

    if [ ! -f "$SOURCE" ]; then
        printf 'ERRORE: sorgente non trovata:\n%s\n' "$SOURCE"
        return 1
    fi

    if [ ! -d "$RES" ]; then
        printf 'ERRORE: resource Android non trovate:\n%s\n' "$RES"
        return 1
    fi

    mkdir -p \
        "$OUT/drawable-nodpi" \
        "$OUT/layout" \
        "$OUT/values" \
        "$PREVIEW" \
        || return 1

    printf '\n===== MASTER DALLO SVG RADIO ATENE =====\n'

    magick \
        -background none \
        -density 600 \
        "$SOURCE" \
        -alpha on \
        -trim \
        +repage \
        -resize 1600x1600 \
        -strip \
        "$MASTER" \
        || return 1

    if [ ! -s "$MASTER" ]; then
        printf 'ERRORE: master PNG non generato.\n'
        return 1
    fi

    magick identify "$MASTER"

    printf '\n===== ASSET ANDROID =====\n'

    for SPEC in \
        "mdpi:48:108:24" \
        "hdpi:72:162:36" \
        "xhdpi:96:216:48" \
        "xxhdpi:144:324:72" \
        "xxxhdpi:192:432:96"
    do
        IFS=':' read -r \
            DENSITY \
            LEGACY \
            FOREGROUND \
            NOTIFICATION \
            <<< "$SPEC"

        mkdir -p \
            "$OUT/mipmap-$DENSITY" \
            "$OUT/drawable-$DENSITY" \
            || return 1

        INNER=$((LEGACY * 80 / 100))
        FOREGROUND_INNER=$((FOREGROUND * 62 / 100))
        NOTIFICATION_INNER=$((NOTIFICATION * 82 / 100))

        MARGIN=$((LEGACY * 4 / 100))
        RADIUS=$((LEGACY * 18 / 100))
        CENTER=$((LEGACY / 2))

        printf '\n--- %s ---\n' "$DENSITY"

        # Launcher legacy quadrato arrotondato.
        magick \
            -size "${LEGACY}x${LEGACY}" \
            xc:none \
            -fill "$BG" \
            -draw "roundrectangle \
                ${MARGIN},${MARGIN} \
                $((LEGACY - MARGIN - 1)),$((LEGACY - MARGIN - 1)) \
                ${RADIUS},${RADIUS}" \
            \( \
                "$MASTER" \
                -resize "${INNER}x${INNER}" \
            \) \
            -gravity center \
            -compose over \
            -composite \
            -strip \
            "$OUT/mipmap-$DENSITY/ic_launcher.png" \
            || return 1

        # Launcher legacy tondo.
        magick \
            -size "${LEGACY}x${LEGACY}" \
            xc:none \
            -fill "$BG" \
            -draw "circle \
                ${CENTER},${CENTER} \
                ${CENTER},${MARGIN}" \
            \( \
                "$MASTER" \
                -resize "${INNER}x${INNER}" \
            \) \
            -gravity center \
            -compose over \
            -composite \
            -strip \
            "$OUT/mipmap-$DENSITY/ic_launcher_round.png" \
            || return 1

        # Adaptive foreground.
        magick \
            "$MASTER" \
            -resize "${FOREGROUND_INNER}x${FOREGROUND_INNER}" \
            -gravity center \
            -background none \
            -extent "${FOREGROUND}x${FOREGROUND}" \
            -strip \
            "$OUT/mipmap-$DENSITY/ic_launcher_foreground.png" \
            || return 1

        # Notification Android: maschera monocromatica bianca.
        MASK="$WORK/notification-mask-$DENSITY.png"

        magick \
            "$MASTER" \
            -alpha extract \
            -threshold 1% \
            -resize "${NOTIFICATION_INNER}x${NOTIFICATION_INNER}" \
            -gravity center \
            -background black \
            -extent "${NOTIFICATION}x${NOTIFICATION}" \
            "$MASK" \
            || return 1

        magick \
            -size "${NOTIFICATION}x${NOTIFICATION}" \
            xc:white \
            "$MASK" \
            -alpha off \
            -compose CopyOpacity \
            -composite \
            -strip \
            "$OUT/drawable-$DENSITY/ic_notification.png" \
            || return 1

        rm -f "$MASK"

        printf 'OK  launcher            %sx%s\n' "$LEGACY" "$LEGACY"
        printf 'OK  launcher round      %sx%s\n' "$LEGACY" "$LEGACY"
        printf 'OK  adaptive foreground %sx%s\n' "$FOREGROUND" "$FOREGROUND"
        printf 'OK  notification        %sx%s\n' "$NOTIFICATION" "$NOTIFICATION"
    done

    printf '\n===== ADAPTIVE BACKGROUND =====\n'

    cat > "$OUT/values/ic_launcher_background.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#101718</color>
</resources>
XML

    printf '\n===== SPLASH =====\n'

    magick \
        "$MASTER" \
        -resize 840x840 \
        -gravity center \
        -background none \
        -extent 1000x1000 \
        -strip \
        "$OUT/drawable-nodpi/bmj_launch_logo.png" \
        || return 1

    cat > "$OUT/values/bmj_branding_colors.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="bmj_launch_background">#101718</color>
</resources>
XML

    cat > "$OUT/layout/launch_screen.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/bmj_launch_background">

    <ImageView
        android:layout_width="300dp"
        android:layout_height="300dp"
        android:layout_centerInParent="true"
        android:contentDescription="@string/app_name"
        android:scaleType="fitCenter"
        android:src="@drawable/bmj_launch_logo" />

</RelativeLayout>
XML

    printf '\n===== VALIDAZIONE DIMENSIONI =====\n'

    for SPEC in \
        "mdpi:48:108:24" \
        "hdpi:72:162:36" \
        "xhdpi:96:216:48" \
        "xxhdpi:144:324:72" \
        "xxxhdpi:192:432:96"
    do
        IFS=':' read -r \
            DENSITY \
            LEGACY \
            FOREGROUND \
            NOTIFICATION \
            <<< "$SPEC"

        for FILE in \
            "$OUT/mipmap-$DENSITY/ic_launcher.png" \
            "$OUT/mipmap-$DENSITY/ic_launcher_round.png" \
            "$OUT/mipmap-$DENSITY/ic_launcher_foreground.png" \
            "$OUT/drawable-$DENSITY/ic_notification.png"
        do
            if [ ! -s "$FILE" ]; then
                printf 'ERRORE: file assente o vuoto: %s\n' "$FILE"
                return 1
            fi
        done

        printf 'OK  %s\n' "$DENSITY"
    done

    printf '\n===== PREVIEW =====\n'

    magick \
        "$OUT/mipmap-xxxhdpi/ic_launcher.png" \
        -filter point \
        -resize 512x512 \
        "$PREVIEW/01-launcher.png" \
        || return 1

    magick \
        "$OUT/mipmap-xxxhdpi/ic_launcher_round.png" \
        -filter point \
        -resize 512x512 \
        "$PREVIEW/02-round.png" \
        || return 1

    magick \
        -size 512x512 \
        xc:"$BG" \
        \( \
            "$OUT/mipmap-xxxhdpi/ic_launcher_foreground.png" \
            -resize 432x432 \
        \) \
        -gravity center \
        -compose over \
        -composite \
        "$PREVIEW/03-adaptive.png" \
        || return 1

    magick \
        -size 512x512 \
        xc:"$BG" \
        \( \
            "$OUT/drawable-xxxhdpi/ic_notification.png" \
            -resize 340x340 \
        \) \
        -gravity center \
        -compose over \
        -composite \
        "$PREVIEW/04-notification.png" \
        || return 1

    magick \
        -size 512x512 \
        xc:"$BG" \
        \( \
            "$OUT/drawable-nodpi/bmj_launch_logo.png" \
            -resize 420x420 \
        \) \
        -gravity center \
        -compose over \
        -composite \
        "$PREVIEW/05-splash.png" \
        || return 1

    magick montage \
        "$PREVIEW/01-launcher.png" \
        "$PREVIEW/02-round.png" \
        "$PREVIEW/03-adaptive.png" \
        "$PREVIEW/04-notification.png" \
        "$PREVIEW/05-splash.png" \
        -background "$BG" \
        -geometry 420x420+16+16 \
        -tile 5x1 \
        "$WORK/android-assets-preview.png" \
        || return 1

    printf '\n===== CHECKSUM =====\n'

    (
        cd "$WORK" || return 1

        find android \
            -type f \
            -print |
        sort |
        while IFS= read -r FILE; do
            shasum -a 256 "$FILE"
        done
    ) > "$WORK/SHA256SUMS"

    printf '\n===== REPOSITORY NON MODIFICATA =====\n'

    cd "$ROOT" || return 1
    git status --short

    printf '\n===== STAGING COMPLETATO =====\n'
    printf '%s\n' "$WORK"

    printf '%s' "$WORK" | pbcopy

    open "$WORK/android-assets-preview.png"
    open "$WORK"

    return 0
}

main "$@"
