# ==============================================================================
# Fish Shell Developer Environment Dockerfile
# Based on Ubuntu 26.04
# Adapted from Dockerfile.zsh
# ==============================================================================

FROM ubuntu:26.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Build arguments for user customization
ARG USERNAME=eli
ARG USER_UID=1002
ARG USER_GID=$USER_UID

# Upgrade and install basic system packages
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    apt-utils \
    sudo \
    wget \
    curl \
    git \
    grc \
    fish \
    ripgrep \
    bat \
    tini \
    iputils-ping \
    ethtool \
    fping \
    iftop \
    virtualenv \
    python3 \
    python3-pip \
    python3-venv \
    python-is-python3 \
    util-linux \
    openssl \
    netcat-openbsd \
    dnsutils \
    yq \
    jq \
    neovim \
    strace \
    eza \
    ldap-utils \
    ca-certificates \
    xz-utils \
    unzip \
    build-essential \
    zoxide && \
    apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Create non-root user and configure Fish as their shell
RUN groupadd -g $USER_GID $USERNAME && \
    useradd -u $USER_UID -g $USER_GID -m -s /usr/bin/fish $USERNAME && \
    echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME

# Copy system-wide configurations (using wildcards to make optional files safe)
COPY motd* /etc/motd
COPY pip.conf* /etc/

# Download and install Teller Secret Manager (v2.0.7)
RUN wget https://github.com/tellerops/teller/releases/download/v2.0.7/teller-x86_64-linux.tar.xz -O /tmp/teller.tar.xz && \
    tar -xf /tmp/teller.tar.xz -C /tmp/ && \
    cp /tmp/teller-x86_64-linux/teller /usr/bin/teller && \
    rm -rf /tmp/teller*

# Optional legacy libssl1.1 for compatibility with older tools if needed
RUN wget http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb -O /tmp/libssl1.1.deb || true && \
    dpkg -i /tmp/libssl1.1.deb || true && \
    rm -f /tmp/libssl1.1.deb

# Download and install Go (v1.26.3)
RUN wget https://go.dev/dl/go1.26.3.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -xzf /tmp/go.tar.gz -C /usr/local/ && \
    rm -f /tmp/go.tar.gz

# Install Starship Prompt globally
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

# Install Terraform (v1.10.5)
RUN wget https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip -O /tmp/terraform.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin/ && \
    rm -f /tmp/terraform.zip

# Install Helm (v3)
RUN curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 /tmp/get_helm.sh && \
    /tmp/get_helm.sh && \
    rm -f /tmp/get_helm.sh

# Install Helmfile
RUN curl -L https://github.com/helmfile/helmfile/releases/latest/download/helmfile_Linux_amd64 -o /usr/local/bin/helmfile && \
    chmod +x /usr/local/bin/helmfile

# Switch to the non-root user
USER $USERNAME
WORKDIR /home/$USERNAME

# Setup custom directories
RUN mkdir -p /home/$USERNAME/.pip \
    /home/$USERNAME/.config/fish/conf.d \
    /home/$USERNAME/bin \
    /home/$USERNAME/.virtualenvs

# Copy user configurations (using wildcards to prevent build failures if missing)
COPY pip.conf* /home/$USERNAME/.pip/
COPY kubectl-ai* /home/$USERNAME/bin/kubectl-ai
COPY motd* /home/$USERNAME/motd

# Setup LazyVim and custom nvim adjustments
RUN git clone https://github.com/LazyVim/starter ~/.config/nvim && \
    git clone https://github.com/LazyVim/LazyVim ~/.local/share/nvim/lazy/lazy.nvim && \
    rm -rf ~/.local/share/nvim/lazy/

# Copy LazyVim plugin adjustment files if they exist in build context
COPY vim_notify.lua* ~/.config/nvim/lua/plugins/
COPY mason-nvim.lua* ~/.config/nvim/lua/plugins/
COPY cds.lua* ~/.config/nvim/lua/config/
COPY rest.lua* ~/.config/nvim/lua/plugins/
COPY keymaps.lua* ~/.config/nvim/lua/config/
COPY options.lua* ~/.config/nvim/lua/config/

# Copy tree-sitter-cds query files for Neovim syntax highlighting
ADD https://github.com/cap-js-community/tree-sitter-cds/raw/main/nvim/locals.scm ~/.config/nvim/queries/cds/
ADD https://github.com/cap-js-community/tree-sitter-cds/raw/main/nvim/folds.scm ~/.config/nvim/queries/cds/
ADD https://github.com/cap-js-community/tree-sitter-cds/raw/main/nvim/highlights.scm ~/.config/nvim/queries/cds/
ADD https://github.com/cap-js-community/tree-sitter-cds/raw/main/nvim/indents.scm ~/.config/nvim/queries/cds/
ADD https://github.com/cap-js-community/tree-sitter-cds/raw/main/nvim/injections.scm ~/.config/nvim/queries/cds/

# Install uv Python package manager
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Google Cloud SDK
RUN curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=/home/$USERNAME

# Install kubectl gcloud component
RUN /home/$USERNAME/google-cloud-sdk/bin/gcloud components install kubectl --quiet

# Install Oh My Fish (OMF)
RUN curl -L https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install > /tmp/install.fish && \
    fish /tmp/install.fish --noninteractive && \
    rm -f /tmp/install.fish

# Configure Fish modular startup configurations
RUN echo 'starship init fish | source' > ~/.config/fish/conf.d/starship.fish && \
    echo 'zoxide init fish | source' > ~/.config/fish/conf.d/zoxide.fish && \
    echo 'if test -f /home/$USERNAME/google-cloud-sdk/path.fish.inc; source /home/$USERNAME/google-cloud-sdk/path.fish.inc; end' > ~/.config/fish/conf.d/gcloud.fish && \
    echo 'fish_add_path -g "$HOME/bin" "$HOME/.local/bin" "/usr/local/go/bin" "$HOME/google-cloud-sdk/bin"' > ~/.config/fish/conf.d/paths.fish && \
    echo 'alias c "clear"' > ~/.config/fish/config.fish && \
    echo 'alias k "kubectl"' >> ~/.config/fish/config.fish && \
    echo 'alias gs "gcloud storage"' >> ~/.config/fish/config.fish && \
    echo 'alias tf "terraform"' >> ~/.config/fish/config.fish


# Default to Fish shell
ENTRYPOINT [ "/usr/bin/fish" ]
