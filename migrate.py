#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess
import re
import argparse
from pathlib import Path

# Terminal color helper constants
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
BLUE = "\033[94m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

# Standard paths that should not be explicitly added to Fish's user paths
STANDARD_PATHS = {
    "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    "/usr/local/bin", "/usr/local/sbin", "/usr/games",
    "/usr/local/games", "/snap/bin"
}

# Standard environment variables to skip
STANDARD_ENV_VARS = {
    "USER", "HOME", "PWD", "OLDPWD", "LS_COLORS", "SHELL", "SHLVL", "_",
    "PATH", "TERM", "LANG", "DISPLAY", "LOGNAME", "MAIL", "HOSTNAME",
    "XDG_DATA_DIRS", "XDG_CONFIG_DIRS", "XDG_RUNTIME_DIR", "XDG_SESSION_ID",
    "XDG_SESSION_TYPE", "XDG_SESSION_CLASS", "SSH_CLIENT", "SSH_CONNECTION",
    "SSH_TTY", "DBUS_SESSION_BUS_ADDRESS", "COLORTERM", "LESS", "PAGER",
    "AUTO_UPDATER_PROJECT", "AUTO_UPDATER_ZONE", "CLOUDSDK_CONFIG"
}

def log_info(msg):
    print(f"{BLUE}[🔍 INFO]{RESET} {msg}")

def log_success(msg):
    print(f"{GREEN}[🟢 SUCCESS]{RESET} {BOLD}{msg}{RESET}")

def log_warning(msg):
    print(f"{YELLOW}[⚠️ WARNING]{RESET} {msg}")

def log_error(msg):
    print(f"{RED}[❌ ERROR]{RESET} {BOLD}{msg}{RESET}", file=sys.stderr)

def get_zsh_resolved_data():
    """
    Launch zsh interactively as a login shell to output active PATH, aliases, and environment.
    We use custom markers to isolate our output from any login banners or interactive clutter.
    """
    log_info("Querying Zsh to extract active PATH, aliases, and environment variables...")
    
    command = (
        'echo "___START_MIGRATION_EXTRACTION___"; '
        'echo "___PATH___"; echo "$PATH"; '
        'echo "___ALIAS___"; alias; '
        'echo "___ENV___"; printenv; '
        'echo "___END_MIGRATION_EXTRACTION___"'
    )
    
    try:
        # Run zsh as an interactive login shell to ensure all files (.zshrc, .zprofile, etc.) are sourced.
        result = subprocess.run(
            ["zsh", "-i", "-l", "-c", command],
            capture_output=True,
            text=True,
            timeout=10 # Set a timeout to prevent hanging on interactive prompts
        )
        output = result.stdout
    except subprocess.TimeoutExpired:
        log_warning("Zsh query timed out. Sourcing Zsh configuration files took too long or was waiting for input.")
        log_info("Attempting non-interactive shell fallback...")
        try:
            result = subprocess.run(
                ["zsh", "-c", command],
                capture_output=True,
                text=True,
                timeout=5
            )
            output = result.stdout
        except Exception as e:
            log_error(f"Failed to query Zsh shell: {e}")
            return None
    except FileNotFoundError:
        log_error("Zsh is not installed or not found in PATH.")
        return None

    # Parse output between markers
    if "___START_MIGRATION_EXTRACTION___" not in output:
        log_error("Could not capture configuration from Zsh output. Ensure Zsh works without blocking prompts.")
        return None

    # Extract clean blocks using markers
    try:
        migration_block = output.split("___START_MIGRATION_EXTRACTION___")[1].split("___END_MIGRATION_EXTRACTION___")[0]
        
        path_block = migration_block.split("___PATH___")[1].split("___ALIAS___")[0].strip()
        alias_block = migration_block.split("___ALIAS___")[1].split("___ENV___")[0].strip()
        env_block = migration_block.split("___ENV___")[1].strip()
        
        return {
            "path": path_block,
            "aliases": alias_block,
            "env": env_block
        }
    except IndexError:
        log_error("Parsing error: Captured data blocks were incomplete.")
        return None

def parse_paths(path_str):
    """
    Split the PATH string and filter out standard system directories.
    """
    raw_paths = path_str.split(":")
    custom_paths = []
    
    for p in raw_paths:
        p = p.strip()
        if not p:
            continue
        # Expand any home directories
        p_resolved = str(Path(p).expanduser().resolve()) if p.startswith("~") or p.startswith("/") else p
        
        # Check against standard paths
        if p not in STANDARD_PATHS and p_resolved not in STANDARD_PATHS:
            if p not in custom_paths:
                custom_paths.append(p)
                
    return custom_paths

def parse_aliases(alias_str):
    """
    Parse Zsh aliases. Zsh outputs them as:
    aliasname=aliasvalue
    or aliasname='aliasvalue'
    """
    aliases = {}
    lines = alias_str.splitlines()
    
    for line in lines:
        line = line.strip()
        if not line or "=" not in line:
            continue
        
        name, val = line.split("=", 1)
        name = name.strip()
        val = val.strip()
        
        # Remove single or double quotes surrounding the value
        if val.startswith("'") and val.endswith("'"):
            val = val[1:-1]
        elif val.startswith('"') and val.endswith('"'):
            val = val[1:-1]
            
        # Clean Zsh specific escaping or single quotes inside values
        # e.g., git commit alias might be escaped
        aliases[name] = val
        
    return aliases

def parse_env_vars(env_str):
    """
    Parse environment variables and filter out system/default ones.
    """
    env_vars = {}
    lines = env_str.splitlines()
    
    for line in lines:
        line = line.strip()
        if not line or "=" not in line:
            continue
            
        name, val = line.split("=", 1)
        name = name.strip()
        val = val.strip()
        
        if name not in STANDARD_ENV_VARS and not name.startswith("_"):
            env_vars[name] = val
            
    return env_vars

def check_package_manager():
    """
    Detect the system's package manager.
    """
    if shutil.which("apt-get"):
        return "apt"
    elif shutil.which("pacman"):
        return "pacman"
    elif shutil.which("dnf"):
        return "dnf"
    elif shutil.which("yum"):
        return "yum"
    elif shutil.which("brew"):
        return "brew"
    return None

def install_fish_if_missing():
    """
    Check if Fish is installed, and if not, install it using the system package manager.
    """
    if shutil.which("fish"):
        log_info("Fish shell is already installed.")
        return True
        
    log_info("Fish shell is missing. Attempting to install...")
    pm = check_package_manager()
    
    if not pm:
        log_error("Could not find a supported package manager (apt-get, pacman, dnf, yum, brew). Please install Fish manually.")
        return False
        
    try:
        if pm == "apt":
            log_info("Running: sudo apt-get update && sudo apt-get install -y fish git curl")
            subprocess.run("sudo apt-get update && sudo apt-get install -y fish git curl", shell=True, check=True)
        elif pm == "pacman":
            log_info("Running: sudo pacman -Sy --noconfirm fish git curl")
            subprocess.run("sudo pacman -Sy --noconfirm fish git curl", shell=True, check=True)
        elif pm == "dnf":
            log_info("Running: sudo dnf install -y fish git curl")
            subprocess.run("sudo dnf install -y fish git curl", shell=True, check=True)
        elif pm == "yum":
            log_info("Running: sudo yum install -y fish git curl")
            subprocess.run("sudo yum install -y fish git curl", shell=True, check=True)
        elif pm == "brew":
            log_info("Running: brew install fish git curl")
            subprocess.run("brew install fish git curl", shell=True, check=True)
        log_success("Fish installed successfully.")
        return True
    except subprocess.CalledProcessError as e:
        log_error(f"Installation failed: {e}")
        return False

def install_oh_my_fish():
    """
    Install Oh My Fish (OMF).
    """
    omf_dir = Path("~/.local/share/omf").expanduser()
    if omf_dir.exists():
        log_info("Oh My Fish (OMF) appears to be already installed.")
        return True
        
    log_info("Installing Oh My Fish (OMF)...")
    try:
        # Run OMF non-interactive installer using fish
        omf_install_cmd = "curl -L https://get.oh.my.fish | fish --non-interactive"
        log_info(f"Running command: {omf_install_cmd}")
        subprocess.run(omf_install_cmd, shell=True, check=True)
        log_success("Oh My Fish installed successfully.")
        return True
    except subprocess.CalledProcessError as e:
        log_warning(f"Oh My Fish installation command returned an error: {e}")
        log_info("Retrying standard interactive OMF install...")
        try:
            subprocess.run("curl -L https://get.oh.my.fish | fish", shell=True, check=True)
            return True
        except Exception as ex:
            log_error(f"Failed to install Oh My Fish: {ex}")
            return False

def write_fish_config(custom_paths, aliases, env_vars, dry_run=False):
    """
    Write modular fish configurations under ~/.config/fish/conf.d/
    """
    config_dir = Path("~/.config/fish/conf.d").expanduser()
    
    path_file = config_dir / "migration_paths.fish"
    alias_file = config_dir / "migration_aliases.fish"
    env_file = config_dir / "migration_env.fish"
    
    # Generate Path commands
    path_lines = ["# Automatically migrated from Zsh by migrate.py", ""]
    for p in custom_paths:
        path_lines.append(f'fish_add_path -g "{p}"')
    path_content = "\n".join(path_lines) + "\n"
    
    # Generate Alias commands
    alias_lines = ["# Automatically migrated from Zsh by migrate.py", ""]
    for name, val in aliases.items():
        # Escape any double quotes or backslashes in fish alias definitions
        escaped_val = val.replace('\\', '\\\\').replace('"', '\\"')
        alias_lines.append(f'alias {name} "{escaped_val}"')
    alias_content = "\n".join(alias_lines) + "\n"
    
    # Generate Env variables
    env_lines = ["# Automatically migrated from Zsh by migrate.py", ""]
    for name, val in env_vars.items():
        # Escape any double quotes
        escaped_val = val.replace('\\', '\\\\').replace('"', '\\"')
        env_lines.append(f'set -gx {name} "{escaped_val}"')
    env_content = "\n".join(env_lines) + "\n"
    
    if dry_run:
        print("\n" + "="*60)
        print(f"{BLUE}{BOLD}DRY RUN PREVIEW{RESET}")
        print("="*60)
        
        print(f"\n{CYAN}{BOLD}File: {path_file}{RESET}")
        print("-" * len(str(path_file)))
        print(path_content.strip())
        
        print(f"\n{CYAN}{BOLD}File: {alias_file}{RESET}")
        print("-" * len(str(alias_file)))
        print(alias_content.strip())
        
        print(f"\n{CYAN}{BOLD}File: {env_file}{RESET}")
        print("-" * len(str(env_file)))
        print(env_content.strip())
        
        print("\n" + "="*60)
        return True

    # Real mode
    try:
        config_dir.mkdir(parents=True, exist_ok=True)
        
        path_file.write_text(path_content)
        log_success(f"Wrote PATH configuration to: {path_file}")
        
        alias_file.write_text(alias_content)
        log_success(f"Wrote ALIAS configuration to: {alias_file}")
        
        env_file.write_text(env_content)
        log_success(f"Wrote ENV configuration to: {env_file}")
        
        return True
    except Exception as e:
        log_error(f"Failed to write configuration files: {e}")
        return False

def change_default_shell():
    """
    Prompt and assist the user in changing their default shell to Fish.
    """
    fish_path = shutil.which("fish")
    if not fish_path:
        log_error("Fish path could not be resolved. Skipping default shell change.")
        return
        
    current_shell = os.environ.get("SHELL", "")
    if "fish" in current_shell:
        log_info("Fish is already set as your current active shell.")
        return

    print(f"\n{BOLD}Would you like to change your default shell to Fish?{RESET}")
    print(f"Current shell: {current_shell}")
    print(f"New shell:     {fish_path}")
    
    try:
        # Prompt user
        choice = input(f"{BOLD}[y/N]: {RESET}").strip().lower()
        if choice in ("y", "yes"):
            log_info(f"Running chsh to change shell to: {fish_path}")
            subprocess.run(f"chsh -s '{fish_path}'", shell=True, check=True)
            log_success("Default shell changed to Fish. Please restart your terminal/session for changes to take effect!")
        else:
            log_info("Skipped default shell change. You can set it manually anytime by running:")
            print(f"  chsh -s {fish_path}")
    except KeyboardInterrupt:
        print()
        log_info("Skipped default shell change.")
    except subprocess.CalledProcessError as e:
        log_warning(f"Could not change default shell: {e}")
        log_info("You might need to change it manually or ensure your user is allowed to run chsh.")

def main():
    parser = argparse.ArgumentParser(
        description="Migrate user environment (PATH, aliases, and variables) from Zsh (Oh My Zsh) to Fish (Oh My Fish)."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Perform Zsh extraction and show the generated Fish configurations without writing them or installing packages."
    )
    args = parser.parse_args()

    print(f"{BOLD}{BLUE}==============================================={RESET}")
    print(f"{BOLD}{BLUE}       Zsh to Fish Migration Helper            {RESET}")
    print(f"{BOLD}{BLUE}==============================================={RESET}\n")

    # 1. Query Zsh configuration
    data = get_zsh_resolved_data()
    if not data:
        log_error("Failed to extract active configuration from Zsh. Make sure Zsh is working.")
        sys.exit(1)

    # 2. Parse extracted environments
    custom_paths = parse_paths(data["path"])
    aliases = parse_aliases(data["aliases"])
    env_vars = parse_env_vars(data["env"])

    print(f"\n{BOLD}Captured Statistics:{RESET}")
    print(f"  - Custom PATH directories:  {len(custom_paths)}")
    print(f"  - Clean aliases extracted:  {len(aliases)}")
    print(f"  - Custom env vars extracted: {len(env_vars)}")

    # 3. Dry-run vs Real execution
    if args.dry_run:
        write_fish_config(custom_paths, aliases, env_vars, dry_run=True)
        log_success("Dry run completed successfully. No changes were made to your system.")
    else:
        # Check and Install packages
        if not install_fish_if_missing():
            log_error("Could not verify or install Fish shell. Aborting.")
            sys.exit(1)

        # Write generated configuration files
        if not write_fish_config(custom_paths, aliases, env_vars, dry_run=False):
            log_error("Failed to write migration config files. Aborting.")
            sys.exit(1)

        # Install Oh My Fish
        install_oh_my_fish()

        # Change default shell
        change_default_shell()

        log_success("Migration process completed successfully!")
        log_info("Open a new terminal tab/window, or start 'fish' to enjoy your new shell!")

if __name__ == "__main__":
    main()
