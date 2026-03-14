# dotfiles
A collection of dotfiles, managed with chezmoi.

## Architecture & Conventions

### Zsh Configuration (`~/.zshrc`)
We use a modular approach for shell configuration rather than a massive monolithic file. 

The main `dot_zshrc` file serves only as a loader. It iterates through the `~/.zshrc.d/` directory and sources everything inside it. 

To add configurations, aliases, or functions for a new tool:
1. Create a new file in `dot_zshrc.d/` named after the tool/topic (e.g., `git.zsh`, `docker.zsh`).
2. Place all related functions, exports, and aliases in that file.
3. Run `chezmoi apply`.

**Existing Modules:**
- `aws.zsh`: Helper functions for AWS (`awsp` profile switcher, `ecrlogin` Docker helper).

## Usage

To apply these dotfiles to a new machine using [chezmoi](https://www.chezmoi.io/):

1. **Initialize and Apply in One Step**
   If you have chezmoi installed, run:
   ```bash
   chezmoi init --apply https://github.com/MichielVanderhoydonck/dotfiles.git
   ```
   *(Be sure to replace the GitHub URL if this repository lives elsewhere!)*

2. **Making Changes & Applying Locally**
   When making changes inside the local repository vault (`~/.local/share/chezmoi/` or your cloned directory), apply them to your system with:
   ```bash
   chezmoi apply
   ```

3. **Useful Chezmoi Commands:**
   - `chezmoi cd`: Jump to the local chezmoi source repository.
   - `chezmoi diff`: See what changes will be made before applying them.
   - `chezmoi add <file>`: Start tracking a new file in your system with chezmoi.
