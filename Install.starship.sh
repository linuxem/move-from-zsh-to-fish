#!/usr/bin/env bash
# ==============================================================================
# Starship Prompt Installation & Fish Integration Script
# ==============================================================================
# This script installs the Starship prompt binary to ~/.local/bin and configures
# it to load automatically inside the Fish shell.
# ==============================================================================

# Setup premium terminal colors
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
BLUE="\033[94m"
CYAN="\033[96m"
BOLD="\033[1m"
RESET="\033[0m"

log_info() {
    echo -e "${BLUE}[🔍 INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[🟢 SUCCESS]${RESET} ${BOLD}$1${RESET}"
}

log_warning() {
    echo -e "${YELLOW}[⚠️ WARNING]${RESET} $1"
}

log_error() {
    echo -e "${RED}[❌ ERROR]${RESET} ${BOLD}$1${RESET}" >&2
}

install_starship() {
    # Ensure ~/.local/bin is created
    mkdir -p "$HOME/.local/bin"

    # Check if starship is already installed in the system or locally
    if command -v starship &> /dev/null; then
        log_success "Starship prompt is already installed globally: $(starship --version | head -n 1)"
    elif [ -f "$HOME/.local/bin/starship" ]; then
        log_success "Starship prompt is already installed locally: $($HOME/.local/bin/starship --version | head -n 1)"
    else
        log_info "Installing Starship binary to ~/.local/bin..."
        if curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"; then
            log_success "Starship binary installed successfully!"
        else
            log_error "Failed to download and install Starship prompt."
            exit 1
        fi
    fi
}

configure_fish_starship() {
    log_info "Configuring Fish Shell to load Starship prompt..."
    
    local fish_config_dir="$HOME/.config/fish/conf.d"
    mkdir -p "$fish_config_dir"

    # 1. Ensure local bin is added to PATH in Fish if not already
    local path_config="$fish_config_dir/starship_path.fish"
    if [ ! -f "$path_config" ]; then
        echo -e '# Add ~/.local/bin to PATH for Starship\nfish_add_path -g "$HOME/.local/bin"' > "$path_config"
        log_success "Created path configuration at ${path_config}"
    else
        log_info "Path configuration already exists at ${path_config}"
    fi

    # 2. Add starship init to Fish configuration
    local starship_config="$fish_config_dir/starship.fish"
    if [ ! -f "$starship_config" ]; then
        echo -e '# Initialize Starship prompt\nstarship init fish | source' > "$starship_config"
        log_success "Created Starship initialization at ${starship_config}"
    else
        if ! grep -q "starship init fish" "$starship_config"; then
            echo -e '\n# Initialize Starship prompt\nstarship init fish | source' >> "$starship_config"
            log_success "Added Starship initialization to existing ${starship_config}"
        else
            log_success "Starship is already initialized in ${starship_config}"
        fi
    fi
}

main() {
    echo -e "${BOLD}${CYAN}====================================================${RESET}"
    echo -e "${BOLD}${CYAN}          Starship Prompt Fish Installer            ${RESET}"
    echo -e "${BOLD}${CYAN}====================================================${RESET}\n"

    # Ensure curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "Curl is required to download Starship. Please install curl and try again."
        exit 1
    fi

    install_starship
    configure_fish_starship

    echo -e "\n${BOLD}${CYAN}----------------------------------------------------${RESET}"
    echo -e "Starship installation and integration completed!"
    echo -e "Restart your Fish shell or run the following to apply:"
    echo -e "  ${BOLD}source ~/.config/fish/conf.d/starship.fish${RESET}"
    echo -e "${BOLD}${CYAN}----------------------------------------------------${RESET}\n"
}

main "$@"
