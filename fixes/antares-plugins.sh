#!/usr/bin/env bash

set -Eeuo pipefail

# ------------------------------------------------------------
# Antares Configuration Fixer
# Creates missing configuration files and disables OpenGL.
# ------------------------------------------------------------

readonly DEFAULT_PREFIX="$HOME/.wine"
readonly PREFIX_ROOTS=(
    "$HOME/.wine"
    "$HOME/.wine32"
    "$HOME/.wine64"
    "$HOME/Games"
    "$HOME/.local/share/wineprefixes"
    "$HOME/.local/share/lutris"
    "$HOME/.var/app"
    "$HOME/Applications"
    "/mnt/win"
    "/opt/wineprefixes"
)

declare -a PREFIXES=()
declare -A SEEN_PREFIXES=()

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARNING] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

is_wine_prefix() {
    local prefix="${1/#\~/$HOME}"

    [[ -d "$prefix/drive_c" &&
       ( -d "$prefix/dosdevices" || -f "$prefix/system.reg" ) ]]
}

add_prefix() {
    local prefix="${1/#\~/$HOME}"
    local canonical

    [[ -d "$prefix" ]] || return 0
    is_wine_prefix "$prefix" || return 0

    canonical="$(realpath -e -- "$prefix" 2>/dev/null)" || return 0

    [[ -n "${SEEN_PREFIXES[$canonical]:-}" ]] && return 0

    SEEN_PREFIXES["$canonical"]=1
    PREFIXES+=("$canonical")
}

scan_prefix_root() {
    local root="$1"
    local candidate

    [[ -d "$root" ]] || return 0

    # Check the root itself.
    add_prefix "$root"

    # Check common prefix directory layouts without an unrestricted
    # recursive filesystem scan.
    while IFS= read -r -d '' candidate; do
        add_prefix "$candidate"
    done < <(
        find "$root" -maxdepth 4 \
            \( -type d \( \
                -name .git -o \
                -name node_modules -o \
                -name .cache \
            \) -prune \) -o \
            \( -type f -name system.reg -printf '%h\0' \) \
            2>/dev/null
    )
}

select_prefix() {
    local i
    local choice

    # Prefer the active WINEPREFIX when it points to a valid prefix.
    if [[ -n "${WINEPREFIX:-}" ]] && is_wine_prefix "$WINEPREFIX"; then
        WINEPREFIX="$(realpath -e -- "$WINEPREFIX")"
        log "Using active Wine prefix: $WINEPREFIX"
        return 0
    fi

    # Use the default prefix whenever it exists.
    if is_wine_prefix "$DEFAULT_PREFIX"; then
        WINEPREFIX="$(realpath -e -- "$DEFAULT_PREFIX")"
        log "Using default Wine prefix: $WINEPREFIX"
        return 0
    fi

    log "Default Wine prefix was not found. Searching for Wine prefixes..."

    for root in "${PREFIX_ROOTS[@]}"; do
        scan_prefix_root "$root"
    done

    # Include prefixes from common custom locations supplied by the user.
    if [[ ${#PREFIXES[@]} -eq 0 ]]; then
        warn "No Wine prefixes were found in the predefined locations."
    fi

    if [[ ${#PREFIXES[@]} -eq 0 ]]; then
        printf 'Enter a Wine prefix path, or press Enter to exit: '
        IFS= read -r choice || true

        [[ -n "$choice" ]] || die "No Wine prefix selected."

        is_wine_prefix "$choice" ||
            die "The selected directory is not a valid Wine prefix."

        WINEPREFIX="$(realpath -e -- "$choice")"
        return 0
    fi

    printf '\nDetected Wine prefixes:\n\n'

    for i in "${!PREFIXES[@]}"; do
        printf '  %d) %s\n' "$((i + 1))" "${PREFIXES[$i]}"
    done

    printf '\nSelect a prefix [1-%d]: ' "${#PREFIXES[@]}"
    IFS= read -r choice || die "No selection received."

    [[ "$choice" =~ ^[0-9]+$ ]] ||
        die "Invalid selection."

    (( choice >= 1 && choice <= ${#PREFIXES[@]} )) ||
        die "Selection is out of range."

    WINEPREFIX="${PREFIXES[$((choice - 1))]}"
    log "Selected Wine prefix: $WINEPREFIX"
}

configure_antares() {
    local plugin
    local file

    local antares_dir="$WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Antares"

    mkdir -p -- "$antares_dir"
    log "Configuration directory: $antares_dir"

    local -a plugins=(
        "Auto-Tune Pro"
        "Auto-Tune Pro X"
        "Auto-Tune Pro 11"
        "Auto-Tune Artist"
        "Auto-Tune EFX+"
        "Auto-Tune EFX+ 10"
        "Auto-Tune Access"
        "Auto-Tune Access 10"
        "Auto-Tune Slice"
        "Auto-Tune Vocal EQ"
        "Auto-Tune Vocodist"
        "Auto-Tune Hybrid"
        "Auto-Tune Vocal Compressor"
        "Auto-Tune Vocal De-Esser"
        "Auto-Tune Vocal Reverb"
        "Auto-Tune SoundSoap"
        "Auto-Key"
        "Auto-Key 2"
        "Harmony Engine"
        "Mic Mod"
        "Mutator"
        "Articulator"
        "Warm"
        "Aspire"
        "Throat"
        "Duo"
        "Choir"
        "Punch"
        "Sybil"
    )

    for plugin in "${plugins[@]}"; do
        file="$antares_dir/$plugin.xml"

        if [[ ! -f "$file" ]]; then
            cat > "$file" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<PROPERTIES>
  <VALUE name="OpenGLPref_ID" val="0"/>
  <VALUE name="StereoRefPref_ID" val="0"/>
  <VALUE name="MIDIInputChannelPref_ID" val="0"/>
</PROPERTIES>
EOF
            log "Created: $plugin.xml"
        else
            # Replace existing OpenGL preference values without
            # changing the other settings.
            if grep -q 'OpenGLPref_ID' "$file"; then
                sed -i \
                    -e 's/\(<VALUE name="OpenGLPref_ID" val="\)[^"]*\("\s*\/>\)/\10\2/g' \
                    -e 's/OpenGLPref_ID="1"/OpenGLPref_ID="0"/g' \
                    "$file"
            else
                # Insert the setting into an existing PROPERTIES node.
                if grep -q '</PROPERTIES>' "$file"; then
                    sed -i \
                        's#</PROPERTIES>#  <VALUE name="OpenGLPref_ID" val="0"/>\n</PROPERTIES>#' \
                        "$file"
                else
                    warn "Could not find a PROPERTIES element in $file"
                    continue
                fi
            fi

            log "Updated: $plugin.xml"
        fi
    done

    log "Antares configuration completed."
}

main() {
    [[ -n "${USER:-}" ]] || die "The USER environment variable is not set."

    select_prefix
    configure_antares
}

main "$@"
