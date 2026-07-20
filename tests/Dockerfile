FROM ubuntu:24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install core tools
RUN apt-get update && apt-get install -y \
    curl \
    git \
    zsh \
    sudo \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install chezmoi
RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin

# Set up test user
RUN useradd -m -s /usr/bin/zsh testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER testuser
WORKDIR /home/testuser

# Copy our dotfiles directory into the container
COPY --chown=testuser:testuser . /home/testuser/dotfiles

# Copy the test runner script
COPY --chown=testuser:testuser tests/verify.sh /home/testuser/verify.sh
RUN chmod +x /home/testuser/verify.sh

ENTRYPOINT ["/home/testuser/verify.sh"]
