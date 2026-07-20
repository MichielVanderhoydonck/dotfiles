#!/bin/bash
set -e

echo "=== Starting E2E Dotfiles Test Suite ==="

# 1. Initialize and apply dotfiles locally using chezmoi pointing to the source directory
echo "Initializing and applying dotfiles..."
chezmoi init --source=/home/testuser/dotfiles --apply

# 2. Check that key configuration files exist
echo "Checking dotfiles installation..."
assert_exists() {
    if [ ! -e "$1" ]; then
        echo "❌ Expected file/directory does not exist: $1"
        exit 1
    fi
}

assert_exists "$HOME/.zshrc"
assert_exists "$HOME/.zshrc.d"
assert_exists "$HOME/.zshrc.d/aws.zsh"
assert_exists "$HOME/.zshrc.d/git.zsh"

# 3. Check installed packages
assert_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ Required command not found: $1"
        exit 1
    fi
}

echo "Verifying package installations..."
assert_command fzf
assert_command gum
assert_command eza
assert_command jq
assert_command aws
assert_command steampipe

# 4. Dry-run Zsh configuration to verify there are no syntax errors
echo "Verifying Zsh configuration syntax..."
zsh -n "$HOME/.zshrc"

# Sourcing the configuration to see if it executes without errors
echo "Testing Zsh configuration loading..."
zsh -c 'source ~/.zshrc && echo "Sourced successfully!"'

# 5. Check helper functions are defined in Zsh environment
echo "Verifying helper functions..."
zsh -c '
source ~/.zshrc
functions_to_check=(awsp awse awss awspipe_config gsw gadd gcommit gbranch glog gclean gstash gwtl gwta gwtr)
for func in "${functions_to_check[@]}"; do
    if ! declare -f "$func" >/dev/null; then
        echo "❌ Helper function not found in environment: $func"
        exit 1
    fi
done
echo "All helper functions successfully defined!"
'

echo "=== All Tests Passed Successfully! ==="
