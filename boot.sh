#!/bin/bash

# Set install mode to online since boot.sh is used for curl installations
export OMARCHY_ONLINE_INSTALL=true

# When running via `wget ... | bash`, stdin is the pipe and may be EOF.
# Do NOT rebind stdin (FD 0), since bash may still be reading this script from it.
# Instead, use /dev/tty explicitly for interactive prompts when available.
TTY_IN=""
if [[ -r /dev/tty ]]; then
    TTY_IN="/dev/tty"
fi

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

ansi_art='                 ▄▄▄
 ▄█████▄    ▄███████████▄    ▄███████   ▄███████   ▄███████   ▄█   █▄    ▄█   █▄
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   █▀   ███   ███  ███   ███
███   ███  ███   ███   ███ ▄███▄▄▄███ ▄███▄▄▄██▀  ███       ▄███▄▄▄███▄ ███▄▄▄███
███   ███  ███   ███   ███ ▀███▀▀▀███ ▀███▀▀▀▀    ███      ▀▀███▀▀▀███  ▀▀▀▀▀▀███
███   ███  ███   ███   ███  ███   ███ ██████████  ███   █▄   ███   ███  ▄██   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
 ▀█████▀    ▀█   ███   █▀   ███   █▀   ███   ███  ███████▀   ███   ▀    ▀█████▀ 
                                       ███   █▀                                  '

# Install gum if not present for enhanced UI
install_gum() {
    if ! command -v gum &>/dev/null; then
        echo "Installing gum for elegant interface..."
        ${SUDO:+$SUDO }pacman -S --noconfirm --needed gum 2>/dev/null || {
            echo "Warning: Could not install gum, falling back to basic interface"
            return 1
        }
    fi
}

# Show message with gum or fallback
show_message() {
    if command -v gum &>/dev/null; then
        gum format "$@"
    else
        echo -e "$1"
    fi
}

# Show spinner with gum or fallback
show_spinner() {
    local title="$1"
    shift
    
    if command -v gum &>/dev/null; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        echo "$title..."
        "$@"
    fi
}

# Ask for confirmation with gum or fallback
ask_confirm() {
    if command -v gum &>/dev/null; then
        if [[ -n "${TTY_IN}" ]]; then
            gum confirm "$1" <"${TTY_IN}"
        else
            gum confirm "$1"
        fi
    else
        echo "$1 [Y/n]:"
        if [[ -n "${TTY_IN}" ]]; then
            read -r response <"${TTY_IN}" || return 0
        else
            read -r response || return 0
        fi
        [[ ! "${response}" =~ ^[Nn]$ ]]
    fi
}

clear

# Show banner with gum or fallback
if command -v gum &>/dev/null; then
    gum style \
        --foreground 212 \
        --border double \
        --align center \
        --margin "1 2" \
        --padding "1 2" \
        "$ansi_art" \
        "$(gum style --foreground 212 --bold 'OMARCHY MAC BOOTSTRAP')"

else
    echo -e "\n$ansi_art\n"
fi

# Install gum for better experience
install_gum

# Validate privileges / sudo if needed
if [[ -n "$SUDO" ]]; then
    if ! command -v sudo &>/dev/null; then
        show_message '❌ **Error**: `sudo` is required when not running as root.'
        show_message "Run this script as root, or install sudo and re-run."
        exit 1
    fi

    show_message "🔐 **Validating administrator access...**"
    if ! sudo -v; then
        show_message "❌ **Error**: sudo access required. Please run with proper permissions."
        exit 1
    fi

        # Keep sudo alive during bootstrap
        keep_sudo_alive() {
            while true; do
                sudo -v
                sleep 50
            done
        }

        keep_sudo_alive &
        SUDO_KEEPALIVE_PID=$!

        # Cleanup on exit
        trap 'sudo -k; kill ${SUDO_KEEPALIVE_PID:-} 2>/dev/null' EXIT INT TERM
fi

show_spinner "Installing release download tools" \
    ${SUDO:+$SUDO }pacman -Syu --noconfirm --needed curl gnupg

release_url="https://github.com/${OMARCHY_REPO:-maralcbr/omarchy-mx-mac}/releases/latest/download/install-omarchy-mx-mac"
installer=$(mktemp "${TMPDIR:-/tmp}/install-omarchy-mx-mac.XXXXXXXX")
signature="$installer.sig"
key_home=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-release-key.XXXXXXXX")
chmod 700 "$key_home"
trap 'rm -f "$installer" "$signature"; rm -rf "$key_home"; sudo -k 2>/dev/null || true; kill ${SUDO_KEEPALIVE_PID:-} 2>/dev/null' EXIT INT TERM
curl --proto '=https' --tlsv1.2 --fail --location --retry 3 --output "$installer" "$release_url"
curl --proto '=https' --tlsv1.2 --fail --location --retry 3 --output "$signature" "$release_url.sig"
fingerprint=5983B1CA32CB778F4D74D24ECFF35022CA5B5959
keyring="$key_home/omarchy-release.gpg"
key_url="https://raw.githubusercontent.com/${OMARCHY_REPO:-maralcbr/omarchy-mx-mac}/main/default/omarchy-release.gpg"
curl --proto '=https' --tlsv1.2 --fail --location --retry 3 --output "$keyring" "$key_url"
actual_fingerprint=$(gpg --batch --show-keys --with-colons "$keyring" | awk -F: '$1 == "fpr" { print $10; exit }')
[[ $actual_fingerprint == "$fingerprint" ]] || { echo "Omarchy release key fingerprint mismatch" >&2; exit 1; }
gpgv --keyring "$keyring" "$signature" "$installer"

show_message "The stable release installer will verify the signed release before cloning it."
${SUDO:+$SUDO } bash "$installer"
