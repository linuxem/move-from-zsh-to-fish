#!/usr/bin/env bash
# ==============================================================================
# Fish Shell, Oh My Fish (OMF), and Fisher Installation Script
# ==============================================================================
# This script automatically detects your package manager, installs the Fish shell,
# and configures both the Oh My Fish (OMF) and Fisher plugin managers.
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

# Detection of Package Manager
detect_pm() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v apk &> /dev/null; then
        echo "apk"
    elif command -v brew &> /dev/null; then
        echo "brew"
    else
        echo "none"
    fi
}

# Install necessary dependencies (git, curl)
install_dependencies() {
    local pm=$1
    log_info "Checking and installing pre-requisites (git, curl)..."
    
    # Check if git and curl are already available
    if command -v git &> /dev/null && command -v curl &> /dev/null; then
        log_success "Git and Curl are already installed."
        return 0
    fi

    case "$pm" in
        apt)
            sudo apt-get update && sudo apt-get install -y git curl
            ;;
        dnf)
            sudo dnf install -y git curl
            ;;
        pacman)
            sudo pacman -Sy --noconfirm git curl
            ;;
        yum)
            sudo yum install -y git curl
            ;;
        zypper)
            sudo zypper install -y git curl
            ;;
        apk)
            sudo apk add git curl
            ;;
        brew)
            brew install git curl
            ;;
        *)
            log_warning "Package manager not fully recognized. Please ensure 'git' and 'curl' are installed manually."
            ;;
    esac
}

# Install Fish shell
install_fish() {
    local pm=$1
    
    if command -v fish &> /dev/null; then
        log_success "Fish shell is already installed ($(fish --version))."
        return 0
    fi
    
    log_info "Fish shell not found. Installing..."
    case "$pm" in
        apt)
            # Add fish release PPA for up-to-date fish on Debian/Ubuntu derivatives
            if command -v apt-add-repository &> /dev/null; then
                log_info "Adding official fish-shell PPA for the latest version..."
                sudo apt-add-repository ppa:fish-shell/release-3 -y || log_warning "Could not add PPA. Proceeding with system defaults."
                sudo apt-get update
            fi
            sudo apt-get install -y fish
            ;;
        dnf)
            sudo dnf install -y fish
            ;;
        pacman)
            sudo pacman -S --noconfirm fish
            ;;
        yum)
            sudo yum install -y fish
            ;;
        zypper)
            sudo zypper install -y fish
            ;;
        apk)
            sudo apk add fish
            ;;
        brew)
            brew install fish
            ;;
        *)
            log_error "Could not find a supported package manager to install Fish automatically."
            log_error "Please install Fish manually from https://fishshell.com/ and re-run this script."
            exit 1
            ;;
    esac
    
    if command -v fish &> /dev/null; then
        log_success "Fish shell installed successfully!"
    else
        log_error "Fish shell installation failed."
        exit 1
    fi
}

# Install Oh My Fish (OMF)
install_omf() {
    if [ -d "$HOME/.local/share/omf" ] || [ -d "$HOME/.config/omf" ]; then
        log_success "Oh My Fish (OMF) is already installed."
        return 0
    fi

    log_info "Installing Oh My Fish (OMF)..."
    
    # We execute using fish non-interactively to cleanly bootstrap
    if curl -sL https://get.oh.my.fish | fish --non-interactive; then
        log_success "Oh My Fish (OMF) installed successfully."
    else
        log_error "Failed to install Oh My Fish (OMF) automatically."
        log_info "Attempting alternative bootstrap..."
        local temp_omf
        temp_omf=$(mktemp)
        if curl -sL https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install > "$temp_omf"; then
            fish "$temp_omf" --non-interactive
            rm -f "$temp_omf"
            log_success "Oh My Fish (OMF) installed successfully using backup installer."
        else
            rm -f "$temp_omf"
            log_error "Could not retrieve OMF installer script. Skipping OMF."
        fi
    fi
}

# Install Fisher
install_fisher() {
    mkdir -p "$HOME/.config/fish/functions"
    
    # Check if fisher is already loaded or available
    if fish -c "functions -q fisher" &> /dev/null; then
        log_success "Fisher plugin manager is already installed."
        return 0
    fi

    log_info "Installing Fisher plugin manager..."
    if fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"; then
        log_success "Fisher installed successfully."
    else
        log_error "Failed to install Fisher."
        exit 1
    fi
}

# Install and configure Starship Prompt
install_starship() {
    log_info "Checking and installing Starship prompt..."
    
    # Ensure ~/.local/bin is created
    mkdir -p "$HOME/.local/bin"
    
    # Check if starship is already installed in system or locally
    if command -v starship &> /dev/null; then
        log_success "Starship prompt is already installed globally: $(starship --version | head -n 1)"
    elif [ -f "$HOME/.local/bin/starship" ]; then
        log_success "Starship prompt is already installed locally: $($HOME/.local/bin/starship --version | head -n 1)"
    else
        log_info "Starship not found. Installing locally to ~/.local/bin..."
        if curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"; then
            log_success "Starship binary installed successfully!"
        else
            log_error "Failed to install Starship."
            exit 1
        fi
    fi

    # Configure Starship for Fish shell
    log_info "Configuring Starship for Fish..."
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

# Main Execution Flow
main() {
    echo -e "${BOLD}${CYAN}====================================================${RESET}"
    echo -e "${BOLD}${CYAN}        Fish Shell Environment Installer            ${RESET}"
    echo -e "${BOLD}${CYAN}====================================================${RESET}\n"

    # 1. Detect Package Manager
    local pm
    pm=$(detect_pm)
    log_info "Detected Package Manager: ${BOLD}${pm}${RESET}"

    # 2. Install pre-requisites (git, curl)
    install_dependencies "$pm"

    # 3. Install Fish
    install_fish "$pm"

    # 4. Install Oh My Fish (OMF)
    install_omf

    # 5. Install Fisher
    install_fisher

    # 6. Install Starship Prompt
    install_starship

    # 7. Verify Installation
    echo -e "\n${BOLD}${CYAN}----------------------------------------------------${RESET}"
    echo -e "${BOLD}Checking Installation Status:${RESET}"
    echo -e "${BOLD}----------------------------------------------------${RESET}"
    
    if command -v fish &> /dev/null; then
        echo -e "  - Fish Shell:    ${GREEN}[✓] Installed${RESET} ($(fish --version))"
    else
        echo -e "  - Fish Shell:    ${RED}[✗] Not Found${RESET}"
    fi

    if [ -d "$HOME/.local/share/omf" ] || [ -d "$HOME/.config/omf" ]; then
        echo -e "  - Oh My Fish:    ${GREEN}[✓] Installed${RESET}"
    else
        echo -e "  - Oh My Fish:    ${RED}[✗] Not Found${RESET}"
    fi

    if fish -c "functions -q fisher" &> /dev/null; then
        echo -e "  - Fisher:        ${GREEN}[✓] Installed${RESET}"
    else
        echo -e "  - Fisher:        ${RED}[✗] Not Found${RESET}"
    fi

    if command -v starship &> /dev/null || [ -f "$HOME/.local/bin/starship" ]; then
        local starship_bin="starship"
        if [ -f "$HOME/.local/bin/starship" ]; then
            starship_bin="$HOME/.local/bin/starship"
        fi
        echo -e "  - Starship:      ${GREEN}[✓] Installed${RESET} ($($starship_bin --version | head -n 1))"
    else
        echo -e "  - Starship:      ${RED}[✗] Not Found${RESET}"
    fi
    echo -e "${BOLD}${CYAN}----------------------------------------------------${RESET}\n"

    log_success "All requested components have been processed!"
    
    # Inform about default shell configuration
    local current_shell
    current_shell=$(echo "$SHELL")
    if [[ "$current_shell" != *fish* ]]; then
        log_info "Your current default shell is: ${BOLD}${current_shell}${RESET}"
        log_info "To set Fish as your default shell, run:"
        echo -e "  ${BOLD}chsh -s \$(which fish)${RESET}"
        log_info "To start Fish right now, simply run:"
        echo -e "  ${BOLD}fish${RESET}"
    else
        log_success "Fish is already your default shell."
    fi
}

main "$@"
