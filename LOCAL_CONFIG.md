# Local Configuration Files

This dotfiles repository supports machine-specific configurations through `.local` files. These files extend the main configurations without requiring machine-specific commits.

## 📁 Supported Local Files

### SSH Configuration
**File**: `config/ssh/config.local`
```bash
# Machine-specific SSH hosts
Host work-server
    HostName server.company.com
    User your-username
    IdentityFile ~/.ssh/id_rsa_work

Host personal-vps
    HostName your-server.com
    User root
    Port 2222
```

### Git Configuration  
**File**: `config/git/gitconfig.local`
```ini
[user]
    name = Your Name
    email = you@company.com

[core]
    sshCommand = ssh -i ~/.ssh/id_rsa_work

[url "git@github.com:company/"]
    insteadOf = https://github.com/company/
```

### Zsh Environment
**File**: `shell/zsh/zshenv.local`
```bash
# Machine-specific environment variables
export WORK_EMAIL="you@company.com"
export COMPANY_GITLAB_TOKEN="your-token"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17"

# Machine-specific paths
export WORK_PROJECTS="$HOME/Projects/work"
export PATH="/opt/custom-tools/bin:$PATH"
```

### Zsh Aliases & Functions
**File**: `shell/zsh/zaliases.local`
```bash
# Machine-specific aliases
alias vpn-work='sudo openconnect --protocol=gp work.company.com'
alias ssh-prod='ssh production-server'
alias deploy='kubectl config use-context staging && helm upgrade'

# Quick shortcuts
alias work='cd $WORK_PROJECTS'
alias logs='tail -f /var/log/app.log'
```

### NPM Configuration
**File**: `config/npm/npmrc.local`
```ini
@company:registry=https://npm.company.com/
//npm.company.com/:_authToken=${COMPANY_NPM_TOKEN}
```

## 🔧 How It Works

1. **Main configs automatically source `.local` files**
2. **`.local` files are gitignored** (never committed)
3. **Safe to store sensitive data** in `.local` files

### Integration Examples

**SSH** (`config/ssh/config`):
```bash
# Main config includes local config
Include config.local

# Shared configurations...
```

**Git** (`config/git/gitconfig`):
```ini
[include]
    path = gitconfig.local

# Shared configurations...
```

**Zsh** (`shell/zsh/zshenv`):
```bash
# Load local environment if it exists
[[ -f "$DOTFILES/shell/zsh/zshenv.local" ]] && source "$DOTFILES/shell/zsh/zshenv.local"
```

## 🚀 Quick Setup

### 1. Create your local files:
```bash
# SSH config
cp config/ssh/config.local.template config/ssh/config.local
# Edit with your SSH hosts

# Git config  
cp config/git/gitconfig.local.template config/git/gitconfig.local
# Edit with your user info

# Zsh environment
touch shell/zsh/zshenv.local
# Add your environment variables

# Zsh aliases
touch shell/zsh/zaliases.local  
# Add your machine-specific aliases
```

### 2. Templates (optional)
Create `.template` files for common configurations:

**File**: `config/git/gitconfig.local.template`
```ini
[user]
    name = Your Name Here
    email = your-email@example.com

# Add work-specific or personal git settings here
```

## 📋 Best Practices

### ✅ DO:
- Use `.local` files for machine-specific settings
- Store sensitive data (tokens, keys) in `.local` files
- Document your `.local` files with comments
- Create templates for common configurations

### ❌ DON'T:
- Commit `.local` files to git
- Put shared configurations in `.local` files
- Use absolute paths when relative paths work

## 🔒 Security Notes

- `.local` files are automatically gitignored
- Safe for API keys, tokens, and credentials
- Backup `.local` files separately from main dotfiles
- Consider encrypting backups of sensitive `.local` files

## 📖 Common Use Cases

### Work Machine
```bash
# zshenv.local
export WORK_MODE=1
export COMPANY_VPN="work.company.com"
export KUBE_CONTEXT="work-cluster"

# zaliases.local  
alias vpn='sudo openconnect $COMPANY_VPN'
alias k='kubectl --context=$KUBE_CONTEXT'
alias work-logs='kubectl logs -f deployment/app'
```

### Personal Machine
```bash
# zshenv.local
export BACKUP_DRIVE="/Volumes/ExternalDrive"
export PERSONAL_PROJECTS="$HOME/Code"

# zaliases.local
alias backup='rsync -av ~/Documents/ $BACKUP_DRIVE/Documents/'
alias personal='cd $PERSONAL_PROJECTS'
alias server='ssh personal-vps'
```

### Development Server
```bash
# zshenv.local
export NODE_ENV="development" 
export DEBUG="app:*"
export DATABASE_URL="postgresql://localhost/app_dev"

# zaliases.local
alias start='docker-compose up -d'
alias logs='docker-compose logs -f'
alias db='psql $DATABASE_URL'
```

---

**Note**: All `.local` files are gitignored by default. This keeps your dotfiles clean while allowing machine-specific customization.