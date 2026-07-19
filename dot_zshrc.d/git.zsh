# Git Interactive Helpers
# Interactive Git workflow enhancements using fzf and gum.

# Common dependency checker
function _git_helper_check_deps() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Missing dependency: git is required."
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Missing dependency: fzf is required."
        return 1
    fi
    if ! command -v gum >/dev/null 2>&1; then
        echo "Missing dependency: gum is required."
        return 1
    fi
    
    # Check if we are inside a git repository
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        gum style --foreground 167 "❌ Error: Not in a git repository."
        return 1
    fi
}

# gsw - Switch Branch
# Interactively search and switch to local or remote branches with commit log preview
function gsw() {
    _git_helper_check_deps || return 1

    local branches selected_branch target_branch
    
    # Format list: local branches, then remote branches (filtering out HEAD reference)
    branches=$(git branch --all --color=always --sort=-committerdate | grep -v 'HEAD ->')

    gum style --margin "1 0" --foreground 109 --bold "Select branch to switch to:"
    
    selected_branch=$(echo "$branches" | fzf \
        --ansi \
        --height 15 \
        --layout=reverse \
        --border \
        --prompt="Git Switch > " \
        --preview="git log {1} --graph --oneline --color=always --date=short -n 10" \
        --preview-window="right:60%" \
        --info=inline)

    if [[ -z "$selected_branch" ]]; then
        gum style --foreground 245 "No branch selected."
        return 0
    fi

    # Clean the selected branch name (remove leading space, asterisks, and color codes)
    target_branch=$(echo "$selected_branch" | sed -E 's/^[* ]*//' | awk '{print $1}' | sed 's/remotes\/origin\///')

    gum style --foreground 109 "Switching to $target_branch..."
    if git switch "$target_branch"; then
        gum style --foreground 142 --bold "✅ Switched successfully."
    else
        gum style --foreground 167 "❌ Switch failed."
        return 1
    fi
}

# gadd - Stage/Unstage Files
# Interactively stage or unstage files with diff previews
function gadd() {
    _git_helper_check_deps || return 1

    # Check for preview tool (delta, diff-so-fancy, or default git diff)
    local preview_cmd
    if command -v delta >/dev/null 2>&1; then
        preview_cmd="git diff --color=always -- {} | delta"
    else
        preview_cmd="git diff --color=always -- {}"
    fi

    local selected_files
    # Use git status to list modified, untracked, deleted, etc.
    # Tab to toggle selection, Enter to stage them
    selected_files=$(git -c color.status=always status --short | fzf \
        -m \
        --ansi \
        --height 20 \
        --layout=reverse \
        --border \
        --prompt="Stage/Unstage (Tab to multi-select) > " \
        --preview="file=\$(echo {2..} | sed 's/^-> //'); if [ -f \"\$file\" ] || [ -d \"\$file\" ]; then $preview_cmd; else git diff --color=always --cached -- \$file; fi" \
        --preview-window="right:70%" \
        --info=inline)

    if [[ -z "$selected_files" ]]; then
        gum style --foreground 245 "No files selected."
        return 0
    fi

    # Extract filenames from the selected status lines
    echo "$selected_files" | while read -r line; do
        # Extract filename (handle renamed files which contain '->')
        local file
        file=$(echo "$line" | cut -c 4- | sed 's/^.* -> //')
        
        # Detect status (staged or unstaged)
        local index_status=$(echo "$line" | cut -c 1)
        local work_status=$(echo "$line" | cut -c 2)

        # Stage or unstage depending on current state
        if [[ "$index_status" != " " && "$work_status" == " " ]]; then
            # Staged only -> Unstage
            git restore --staged "$file"
            gum style --foreground 214 "⇄ Unstaged: $file"
        else
            # Unstaged -> Stage
            git add "$file"
            gum style --foreground 142 "➕ Staged: $file"
        fi
    done
}

# gcommit - Conventional Commit Wizard
# Helps write standardized commits matching the Conventional Commits specification
function gcommit() {
    _git_helper_check_deps || return 1

    # Ensure there are staged changes to commit
    if git diff --cached --quiet; then
        gum style --foreground 208 "⚠️ No staged changes found. Please stage files using 'gadd' or 'git add' first."
        return 1
    fi

    # 1. Type
    gum style --margin "1 0" --foreground 109 --bold "Select commit type:"
    local commit_type
    commit_type=$(gum choose \
        "feat: A new feature" \
        "fix: A bug fix" \
        "docs: Documentation only changes" \
        "style: Changes that do not affect the meaning of the code (white-space, formatting, etc)" \
        "refactor: A code change that neither fixes a bug nor adds a feature" \
        "perf: A code change that improves performance" \
        "test: Adding missing tests or correcting existing tests" \
        "build: Changes that affect the build system or external dependencies" \
        "ci: Changes to our CI configuration files and scripts" \
        "chore: Other changes that don't modify src or test files" \
        "revert: Reverts a previous commit")
    
    [[ -z "$commit_type" ]] && return 0
    commit_type=$(echo "$commit_type" | cut -d: -f1)

    # 2. Scope
    local commit_scope
    commit_scope=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "Scope (optional, e.g. auth, parser)" --prompt "Scope > ")

    # 3. Breaking Change toggle
    local is_breaking="No"
    is_breaking=$(gum choose "No" "Yes (Breaking Change)")

    # 4. Short Description
    local commit_desc
    commit_desc=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "Commit message summary (required)" --prompt "Summary > ")
    if [[ -z "$commit_desc" ]]; then
        gum style --foreground 167 "❌ Summary description is required to commit."
        return 1
    fi

    # 5. Body / Detailed Description (Optional)
    local commit_body
    gum style --margin "1 0" --foreground 109 "Detailed description / body (optional, press Esc + Enter to finish):"
    commit_body=$(gum write --placeholder "Enter details here..." --cursor.foreground="208")

    # Build the commit header
    local header="$commit_type"
    if [[ -n "$commit_scope" ]]; then
        header="$header($commit_scope)"
    fi
    if [[ "$is_breaking" == *"Yes"* ]]; then
        header="$header!"
    fi
    header="$header: $commit_desc"

    # Assemble the final commit message
    local temp_msg_file
    temp_msg_file=$(mktemp)
    
    echo "$header" > "$temp_msg_file"
    if [[ -n "$commit_body" ]]; then
        echo "" >> "$temp_msg_file"
        echo "$commit_body" >> "$temp_msg_file"
    fi

    # If breaking change, append footer
    if [[ "$is_breaking" == *"Yes"* ]]; then
        local breaking_desc
        gum style --margin "1 0" --foreground 208 --bold "Enter breaking change details:"
        breaking_desc=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "Describe breaking changes (e.g. API changes, migration steps)" --prompt "BREAKING CHANGE > ")
        if [[ -n "$breaking_desc" ]]; then
            echo "" >> "$temp_msg_file"
            echo "BREAKING CHANGE: $breaking_desc" >> "$temp_msg_file"
        fi
    fi

    gum style --margin "1 0" --foreground 142 --bold "Commit Message Preview:"
    gum style --border normal --border-foreground 109 "$(cat "$temp_msg_file")"

    if gum confirm "Proceed with commit?"; then
        if git commit -F "$temp_msg_file"; then
            gum style --foreground 142 --bold "✅ Staged changes committed successfully."
        else
            gum style --foreground 167 "❌ Commit failed."
        fi
    else
        gum style --foreground 245 "Commit aborted."
    fi

    rm -f "$temp_msg_file"
}

# gbranch - Conventional Branch Creator
# Creates new branches conforming to standard type prefixes in kebab-case
function gbranch() {
    _git_helper_check_deps || return 1

    gum style --margin "1 0" --foreground 109 --bold "Select branch prefix type:"
    local type
    type=$(gum choose "feat" "fix" "chore" "docs" "refactor" "perf" "test" "ci")
    [[ -z "$type" ]] && return 0

    local desc
    desc=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "Branch description (e.g. add new auth system)" --prompt "Description > ")
    if [[ -z "$desc" ]]; then
        gum style --foreground 167 "❌ Description is required."
        return 1
    fi

    # Convert to lowercase, replace spaces and special characters with hyphens (kebab-case)
    local formatted_desc
    formatted_desc=$(echo "$desc" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g')

    local branch_name="${type}/${formatted_desc}"
    gum style --margin "1 0" --foreground 109 "Target branch: $branch_name"

    if gum confirm "Create and checkout branch '$branch_name'?"; then
        if git checkout -b "$branch_name"; then
            gum style --foreground 142 --bold "✅ Branch created and activated."
        else
            gum style --foreground 167 "❌ Failed to create branch."
        fi
    fi
}

# glog - Commit History Browser
# Browse commits interactively and copy SHA on Enter
function glog() {
    _git_helper_check_deps || return 1

    local selected_commit
    # %h: short SHA, %ad: author date, %s: subject, %an: author name
    selected_commit=$(git log --color=always --format="%C(yellow)%h%C(reset) %C(green)%ad%C(reset) %s %C(blue)(%an)%C(reset)" --date=short | fzf \
        --ansi \
        --height 20 \
        --layout=reverse \
        --border \
        --prompt="Git Log > " \
        --preview="git show --color=always {1}" \
        --preview-window="right:60%" \
        --info=inline)

    if [[ -z "$selected_commit" ]]; then
        return 0
    fi

    local commit_sha
    commit_sha=$(echo "$selected_commit" | awk '{print $1}')
    
    # Copy to clipboard if pbcopy (mac) or xclip (linux) is available
    if command -v pbcopy >/dev/null 2>&1; then
        echo -n "$commit_sha" | pbcopy
        gum style --foreground 142 "📋 Copied SHA to clipboard: $commit_sha"
    elif command -v xclip >/dev/null 2>&1; then
        echo -n "$commit_sha" | xclip -selection clipboard
        gum style --foreground 142 "📋 Copied SHA to clipboard: $commit_sha"
    else
        gum style --foreground 109 "Selected Commit SHA: $commit_sha"
    fi
}

# gclean - Branch Cleanup
# Interactively select and delete local branches
function gclean() {
    _git_helper_check_deps || return 1

    # Keep track of current, main, master to avoid deletion
    local current_branch main_branch master_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    local branches to_delete
    # Get all local branches, excluding current branch, main, and master
    branches=$(git branch --format="%(refname:short)" | grep -vE "^(${current_branch}|main|master)$")

    if [[ -z "$branches" ]]; then
        gum style --foreground 142 "🎉 No local branches available for cleanup."
        return 0
    fi

    gum style --margin "1 0" --foreground 109 --bold "Select branches to delete (Tab to multi-select):"
    
    to_delete=$(echo "$branches" | fzf \
        -m \
        --height 15 \
        --layout=reverse \
        --border \
        --prompt="Clean Branches > " \
        --preview="git log {} --graph --oneline --color=always -n 10" \
        --preview-window="right:60%" \
        --info=inline)

    if [[ -z "$to_delete" ]]; then
        gum style --foreground 245 "No branches selected for deletion."
        return 0
    fi

    gum style --margin "1 0" --foreground 208 --bold "Selected branches to delete:"
    echo "$to_delete" | sed 's/^/  - /'

    if gum confirm "Are you sure you want to delete these branches?"; then
        echo "$to_delete" | while read -r branch; do
            if git branch -d "$branch" >/dev/null 2>&1; then
                gum style --foreground 142 "🗑️ Deleted branch: $branch"
            else
                # If unmerged, ask if we want to force delete
                gum style --foreground 208 "⚠️ Branch '$branch' is not fully merged."
                if gum confirm "Force delete '$branch'?"; then
                    if git branch -D "$branch"; then
                        gum style --foreground 142 "🗑️ Force deleted branch: $branch"
                    else
                        gum style --foreground 167 "❌ Failed to delete '$branch'."
                    fi
                fi
            fi
        done
    else
        gum style --foreground 245 "Cleanup canceled."
    fi
}

# gstash - Stash Manager
# Interactive stash selection with diff preview and operation options
function gstash() {
    _git_helper_check_deps || return 1

    local stashes
    stashes=$(git stash list 2>/dev/null)

    if [[ -z "$stashes" ]]; then
        gum style --foreground 142 "No stashes found."
        return 0
    fi

    gum style --margin "1 0" --foreground 109 --bold "Select a stash to manage:"
    
    local selected_stash
    selected_stash=$(echo "$stashes" | fzf \
        --height 15 \
        --layout=reverse \
        --border \
        --prompt="Stash List > " \
        --preview="git stash show --color=always -p {1}" \
        --preview-window="right:60%" \
        --info=inline)

    if [[ -z "$selected_stash" ]]; then
        gum style --foreground 245 "No stash selected."
        return 0
    fi

    # Extract stash ref (e.g. stash@{0})
    local stash_ref
    stash_ref=$(echo "$selected_stash" | grep -oE 'stash@\{[0-9]+\}')

    gum style --margin "1 0" --foreground 109 --bold "Select action for $stash_ref:"
    local action
    action=$(gum choose "show: View files modified" "apply: Apply stash changes & keep stash" "pop: Apply stash changes & remove stash" "drop: Remove stash")

    [[ -z "$action" ]] && return 0
    action=$(echo "$action" | cut -d: -f1)

    case "$action" in
        show)
            git stash show -p "$stash_ref"
            ;;
        apply)
            git stash apply "$stash_ref" && gum style --foreground 142 "✅ Stash applied successfully."
            ;;
        pop)
            git stash pop "$stash_ref" && gum style --foreground 142 "✅ Stash popped successfully."
            ;;
        drop)
            if gum confirm "Are you sure you want to drop $stash_ref?"; then
                git stash drop "$stash_ref" && gum style --foreground 142 "🗑️ Stash dropped."
            fi
            ;;
    esac
}

# gwtl - Git Worktree List & Switch Directory
# Interactively list worktrees and cd to the selected worktree
function gwtl() {
    _git_helper_check_deps || return 1

    local worktrees
    worktrees=$(git worktree list)

    if [[ -z "$worktrees" ]]; then
        gum style --foreground 142 "No worktrees found."
        return 0
    fi

    gum style --margin "1 0" --foreground 109 --bold "Select worktree to switch to:"

    local selected_wt
    selected_wt=$(echo "$worktrees" | fzf \
        --height 12 \
        --layout=reverse \
        --border \
        --prompt="Worktrees > " \
        --preview="git -C {1} status --short 2>/dev/null || ls -la {1}" \
        --preview-window="right:60%" \
        --info=inline)

    if [[ -z "$selected_wt" ]]; then
        gum style --foreground 245 "No worktree selected."
        return 0
    fi

    local wt_path
    wt_path=$(echo "$selected_wt" | awk '{print $1}')

    gum style --foreground 142 "📂 Switching directory to: $wt_path"
    cd "$wt_path" || return 1
}

# gwta - Git Worktree Add
# Interactively create a new worktree for an existing or new conventional branch
function gwta() {
    _git_helper_check_deps || return 1

    gum style --margin "1 0" --foreground 109 --bold "Create worktree from:"
    local branch_source
    branch_source=$(gum choose "Existing branch" "New conventional branch")

    [[ -z "$branch_source" ]] && return 0

    local branch_name=""

    if [[ "$branch_source" == "Existing branch" ]]; then
        local branches
        branches=$(git branch --all --color=always --sort=-committerdate | grep -v 'HEAD ->')
        
        gum style --margin "1 0" --foreground 109 --bold "Select source branch:"
        local selected_branch
        selected_branch=$(echo "$branches" | fzf \
            --ansi \
            --height 15 \
            --layout=reverse \
            --border \
            --prompt="Branch > " \
            --info=inline)

        [[ -z "$selected_branch" ]] && return 0
        branch_name=$(echo "$selected_branch" | sed -E 's/^[* ]*//' | awk '{print $1}' | sed 's/remotes\/origin\///')
    else
        # New conventional branch creation flow
        gum style --margin "1 0" --foreground 109 --bold "Select branch prefix type:"
        local type
        type=$(gum choose "feat" "fix" "chore" "docs" "refactor" "perf" "test" "ci")
        [[ -z "$type" ]] && return 0

        local desc
        desc=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --placeholder "Branch description (e.g. add new feature)" --prompt "Description > ")
        [[ -z "$desc" ]] && return 0

        local formatted_desc
        formatted_desc=$(echo "$desc" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g')
        branch_name="${type}/${formatted_desc}"
    fi

    # Pick a default path based on branch name (replace slashes with hyphens/underscores or keep hierarchy)
    local sanitized_branch_dir
    sanitized_branch_dir=$(echo "$branch_name" | tr '/' '-')
    local default_path="../$sanitized_branch_dir"

    local wt_path
    wt_path=$(gum input --cursor.foreground="208" --placeholder.foreground="245" --prompt.foreground="109" --value "$default_path" --placeholder "Target directory path" --prompt "Path > ")
    [[ -z "$wt_path" ]] && return 0

    gum style --margin "1 0" --foreground 109 "Creating worktree at '$wt_path' for branch '$branch_name'..."

    # Determine command depending on branch existence (if source is new branch, we need to create it)
    if [[ "$branch_source" == "New conventional branch" ]]; then
        if git worktree add -b "$branch_name" "$wt_path"; then
            gum style --foreground 142 --bold "✅ Worktree and new branch created successfully."
            if gum confirm "Switch to the new worktree directory?"; then
                cd "$wt_path" || return 1
            fi
        else
            gum style --foreground 167 "❌ Failed to add worktree."
        fi
    else
        if git worktree add "$wt_path" "$branch_name"; then
            gum style --foreground 142 --bold "✅ Worktree added successfully."
            if gum confirm "Switch to the worktree directory?"; then
                cd "$wt_path" || return 1
            fi
        else
            gum style --foreground 167 "❌ Failed to add worktree."
        fi
    fi
}

# gwtr - Git Worktree Remove
# Interactively select and remove a worktree
function gwtr() {
    _git_helper_check_deps || return 1

    local worktrees
    # Exclude the main/current worktree directory from removal lists to prevent removing active worktree
    local current_wt_path
    current_wt_path=$(git rev-parse --show-toplevel 2>/dev/null)
    
    # Format list, filtering out the current worktree path
    worktrees=$(git worktree list | grep -Fv "$current_wt_path")

    if [[ -z "$worktrees" ]]; then
        gum style --foreground 208 "No other worktrees available to remove."
        return 0
    fi

    gum style --margin "1 0" --foreground 109 --bold "Select worktree to REMOVE (this deletes the directory):"

    local selected_wt
    selected_wt=$(echo "$worktrees" | fzf \
        --height 12 \
        --layout=reverse \
        --border \
        --prompt="Remove Worktree > " \
        --preview="git -C {1} status --short 2>/dev/null || ls -la {1}" \
        --preview-window="right:60%" \
        --info=inline)

    if [[ -z "$selected_wt" ]]; then
        gum style --foreground 245 "No worktree selected."
        return 0
    fi

    local wt_path
    wt_path=$(echo "$selected_wt" | awk '{print $1}')

    gum style --foreground 208 --bold "⚠️ You selected to remove: $wt_path"
    
    if gum confirm "Are you sure you want to remove this worktree?"; then
        # Check if there are unstaged changes
        if ! git -C "$wt_path" diff --quiet 2>/dev/null || ! git -C "$wt_path" diff --cached --quiet 2>/dev/null; then
            gum style --foreground 208 "⚠️ Worktree contains uncommitted changes."
            if gum confirm "Force removal (losing uncommitted changes)?"; then
                if git worktree remove --force "$wt_path"; then
                    gum style --foreground 142 --bold "🗑️ Worktree force-removed."
                else
                    gum style --foreground 167 "❌ Failed to remove worktree."
                fi
            fi
        else
            if git worktree remove "$wt_path"; then
                gum style --foreground 142 --bold "🗑️ Worktree removed."
            else
                gum style --foreground 167 "❌ Failed to remove worktree."
            fi
        fi
    else
        gum style --foreground 245 "Removal canceled."
    fi
}

