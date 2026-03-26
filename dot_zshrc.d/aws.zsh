# AWS Profile Swapper
# Select an AWS profile using fzf, display with gum, and export credentials to environment variables.
function awsp() {
    # Check dependencies
    if ! command -v aws >/dev/null 2>&1 || ! command -v fzf >/dev/null 2>&1 || ! command -v gum >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo "Missing dependencies. Please ensure awscli, fzf, gum, and jq are installed."
        return 1
    fi

    local profiles
    profiles=$(aws configure list-profiles 2>/dev/null | sort)
    
    if [[ -z "$profiles" ]]; then
        gum style --foreground 208 "No AWS profiles found."
        gum style --foreground 245 "Run 'awss' to configure SSO and populate profiles, or set up ~/.aws/config manually."
        return 1
    fi

    gum style --margin "1 0" --foreground 208 --bold "Select an AWS profile:"
    local selected_profile
    selected_profile=$(echo "$profiles" | fzf --height 10 --layout=reverse --border --prompt="AWS Profile > " --info=inline)

    if [[ -z "$selected_profile" ]]; then
        gum style --foreground 245 "No profile selected."
        return 1
    fi

    export AWS_PROFILE="$selected_profile"
    export AWS_DEFAULT_PROFILE="$selected_profile"

    # Export active credentials to environment variables
    # This works for static keys, SSO, assumed roles, etc.
    local creds
    if ! creds=$(aws configure export-credentials --profile "$selected_profile" 2>/dev/null); then
        # Check if it's an SSO profile that might need login
        if aws configure get sso_session --profile "$selected_profile" &>/dev/null || aws configure get sso_start_url --profile "$selected_profile" &>/dev/null; then
            gum style --foreground 214 "SSO session expired or invalid. Attempting to log in..."
            if aws sso login --profile "$selected_profile"; then
                creds=$(aws configure export-credentials --profile "$selected_profile" 2>/dev/null)
            else
                gum style --foreground 167 "❌ AWS SSO login failed."
                return 1
            fi
        fi
    fi

    if [[ -n "$creds" ]]; then
        export AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r .AccessKeyId)
        export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r .SecretAccessKey)
        
        local token
        token=$(echo "$creds" | jq -r .SessionToken)
        if [[ "$token" != "null" && -n "$token" ]]; then
            export AWS_SESSION_TOKEN="$token"
        else
            unset AWS_SESSION_TOKEN
        fi
    else
        # Fallback to static config if export-credentials fails or returns empty unexpectedly
        local access_key
        access_key=$(aws configure get aws_access_key_id --profile "$selected_profile" 2>/dev/null)
        if [[ -n "$access_key" ]]; then
            export AWS_ACCESS_KEY_ID="$access_key"
            export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile "$selected_profile" 2>/dev/null)
            unset AWS_SESSION_TOKEN
        fi
    fi

    # Also extract the region
    local region
    region=$(aws configure get region --profile "$selected_profile" 2>/dev/null)
    if [[ -n "$region" ]]; then
        export AWS_REGION="$region"
        export AWS_DEFAULT_REGION="$region"
    else
        unset AWS_REGION
        unset AWS_DEFAULT_REGION
    fi

    gum style --foreground 142 --bold "✅ Activated AWS Profile: $AWS_PROFILE"
    if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
        gum style --foreground 142 "🔐 Exported credentials to AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    fi
}

# ECR Login Helper
# Automatically log into AWS ECR using current credentials and region
function awse() {
    if ! command -v aws >/dev/null 2>&1 || ! command -v gum >/dev/null 2>&1; then
        echo "Missing dependencies. Please ensure awscli and gum are installed."
        return 1
    fi

    local engine
    if command -v podman >/dev/null 2>&1; then
        engine="podman"
    elif command -v docker >/dev/null 2>&1; then
        engine="docker"
    else
        echo "Missing dependencies. Please ensure docker or podman is installed."
        return 1
    fi

    local region="${AWS_REGION:-${AWS_DEFAULT_REGION}}"
    if [[ -z "$region" ]]; then
        region=$(aws configure get region 2>/dev/null)
    fi

    if [[ -z "$region" ]]; then
        gum style --foreground 214 "AWS Region not set. Please enter region (e.g. us-east-1):"
        region=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "us-east-1")
        if [[ -z "$region" ]]; then
            gum style --foreground 167 "Region is required."
            return 1
        fi
    fi

    gum style --foreground 109 "Fetching AWS Account ID..."
    local account_id
    if ! account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
        gum style --foreground 167 "❌ Failed to get AWS Account ID. Are your credentials valid?"
        return 1
    fi

    local ecr_url="${account_id}.dkr.ecr.${region}.amazonaws.com"
    gum style --foreground 109 "Logging into ECR ($engine): $ecr_url..."

    if aws ecr get-login-password --region "$region" | $engine login --username AWS --password-stdin "$ecr_url" >/dev/null 2>&1; then
        gum style --foreground 142 --bold "✅ Successfully logged into ECR: $ecr_url"
    else
        gum style --foreground 167 "❌ Failed to log into ECR."
        return 1
    fi
}

# AWS SSO Config populator
# Interactively configure SSO, log in, and populate ~/.aws/config with all available accounts and roles.
function awss() {
    # Check dependencies
    if ! command -v aws >/dev/null 2>&1 || ! command -v gum >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo "Missing dependencies. Please ensure awscli, gum, and jq are installed."
        return 1
    fi

    # Ensure ~/.aws directory exists to prevent issues on completely fresh environments
    mkdir -p ~/.aws

    local sso_start_url
    sso_start_url=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "SSO Start URL (e.g. https://my-sso.awsapps.com/start)" --prompt "SSO Start URL > ")
    if [[ -z "$sso_start_url" ]]; then
        gum style --foreground 167 "SSO Start URL is required."
        return 1
    fi

    local sso_region
    sso_region=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "SSO Region" --value "eu-west-1" --prompt "SSO Region > ")
    if [[ -z "$sso_region" ]]; then
        sso_region="eu-west-1"
    fi

    local sso_session_name
    sso_session_name=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "SSO Session Name" --value "my-sso" --prompt "SSO Session Name > ")
    if [[ -z "$sso_session_name" ]]; then
        sso_session_name="my-sso"
    fi

    gum style --foreground 109 "Configuring SSO session in ~/.aws/config..."
    local config_file="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
    touch "$config_file"

    if ! grep -q "^\[sso-session ${sso_session_name}\]" "$config_file" 2>/dev/null; then
        echo "" >> "$config_file"
        echo "[sso-session ${sso_session_name}]" >> "$config_file"
        echo "sso_start_url = ${sso_start_url}" >> "$config_file"
        echo "sso_region = ${sso_region}" >> "$config_file"
        echo "sso_registration_scopes = sso:account:access" >> "$config_file"
    else
        gum style --foreground 245 "SSO session '${sso_session_name}' already exists. Reusing it."
    fi

    gum style --foreground 214 "Attempting SSO login for session '$sso_session_name'..."
    if ! aws sso login --sso-session "$sso_session_name"; then
        gum style --foreground 167 "❌ AWS SSO login failed."
        return 1
    fi

    gum style --foreground 109 "Fetching accounts and populating config..."
    
    # Ensure cache directory exists before trying to read from it
    if [[ ! -d ~/.aws/sso/cache ]]; then
        gum style --foreground 167 "❌ SSO cache directory not found. Login may have failed."
        return 1
    fi

    # Find the latest valid SSO token
    local token
    token=$(jq -r 'select(.accessToken != null) | .accessToken' ~/.aws/sso/cache/*.json 2>/dev/null | head -n 1)

    if [[ -z "$token" ]]; then
        gum style --foreground 167 "❌ Could not find SSO access token in ~/.aws/sso/cache/"
        return 1
    fi

    local accounts_json
    accounts_json=$(aws sso list-accounts --access-token "$token" --region "$sso_region" 2>/dev/null)
    if [[ -z "$accounts_json" ]]; then
        gum style --foreground 167 "❌ Failed to list accounts."
        return 1
    fi

    # Process each account
    jq -c '.accountList[]' <<< "$accounts_json" 2>/dev/null | while read -r account; do
        local account_id=$(echo "$account" | jq -r '.accountId')
        local account_name=$(echo "$account" | jq -r '.accountName' | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -d "'\"")
        
        local roles_json
        roles_json=$(aws sso list-account-roles --account-id "$account_id" --access-token "$token" --region "$sso_region" 2>/dev/null)
        jq -c '.roleList[]' <<< "$roles_json" 2>/dev/null | while read -r role; do
            local role_name=$(echo "$role" | jq -r '.roleName')
            # Profile named according to account only
            local profile_name="${account_name}"
            
            aws configure set sso_session "$sso_session_name" --profile "$profile_name"
            aws configure set sso_account_id "$account_id" --profile "$profile_name"
            aws configure set sso_role_name "$role_name" --profile "$profile_name"
            aws configure set region "$sso_region" --profile "$profile_name"
            gum style --foreground 109 "  → Added profile: $profile_name"
        done
    done

    gum style --foreground 142 --bold "✅ AWS SSO Setup Complete. Run 'awsp' to switch profiles."
}

# Generate Steampipe AWS plugin config
# Creates connection blocks for all AWS profiles and an aggregator connection
function awspipe_config() {
    if ! command -v steampipe >/dev/null 2>&1; then
        return 0
    fi

    local spc_file="$HOME/.steampipe/config/aws.spc"
    mkdir -p "$HOME/.steampipe/config"

    gum style --foreground 109 "Generating Steampipe AWS plugin config..."

    local conn_group_name
    conn_group_name=$(gum input \
        --cursor.foreground="208" \
        --placeholder.foreground="245" \
        --prompt.foreground="109" \
        --placeholder "Steampipe Connection Group (e.g. all)" \
        --value "all" \
        --prompt "Steampipe Connection Group > ")

    [[ -z "$conn_group_name" ]] && conn_group_name="all"

    conn_group_name=$(echo "$conn_group_name" | tr '[:upper:]' '[:lower:]' | tr -dc 'a-z0-9_')
    [[ -z "$conn_group_name" ]] && conn_group_name="all"

    local agg_name="aws_${conn_group_name}"

    # Start fresh config
    : > "$spc_file"

    # Generate connections
    aws configure list-profiles 2>/dev/null | sort | while IFS= read -r p; do
        [[ -z "$p" ]] && continue

        local conn_name
        conn_name=$(echo "$p" | tr '[:upper:]-' '[:lower:]_' | tr -dc 'a-z0-9_')
        conn_name="aws_${conn_name}"

        cat >> "$spc_file" <<EOF
connection "$conn_name" {
  plugin  = "aws"
  profile = "$p"
}

EOF
    done

    # Add aggregator at the end
    cat >> "$spc_file" <<EOF
connection "$agg_name" {
  plugin      = "aws"
  type        = "aggregator"
  connections = ["aws_*"]
}
EOF

    gum style --foreground 142 --bold "✅ Steampipe config generated successfully."
}
