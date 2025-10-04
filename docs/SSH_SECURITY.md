# SSH Security Configuration

## Overview

This dotfiles repository enforces **key-only SSH authentication** on all personal machines (dreams, draco, lucky). Password authentication is completely disabled at both the client and server level.

## Key Features

- ✅ **Public key authentication only** - no password fallback
- ✅ **Passphrase-protected SSH keys** - integrated with macOS Keychain for Touch ID
- ✅ **Hardened sshd_config** - based on OpenSSH defaults with security enhancements
- ✅ **Managed via Dotbot** - idempotent, declarative configuration
- ✅ **Cross-platform** - works on macOS and Linux

---

## Repository Structure

### Client Configuration

**File:** `system/ssh/config`

Key settings in the `Host *` block:
```ssh
AddKeysToAgent yes              # Auto-add keys to agent
UseKeychain yes                 # Use macOS Keychain (macOS only)
PreferredAuthentications publickey  # Try public key first
PasswordAuthentication no       # Disable password auth client-side
IdentityFile ~/.ssh/id_personal # Default key for personal machines
```

**Dotbot linking:** `~/.ssh/config` → `system/ssh/config`

### Server Configuration

**File:** `system/ssh/sshd_config`

Based on the standard OpenSSH default config with these security hardening changes:

| Setting | Value | Purpose |
|---------|-------|---------|
| `PasswordAuthentication` | no | Disable password logins |
| `KbdInteractiveAuthentication` | no | Disable keyboard-interactive auth |
| `PermitEmptyPasswords` | no | Explicitly forbid empty passwords |
| `PubkeyAuthentication` | yes | Enable public key authentication |
| `AuthenticationMethods` | publickey | Require public key authentication only |
| `PermitRootLogin` | prohibit-password | Root must use keys |
| `MaxAuthTries` | 3 | Limit failed attempts (down from 6) |
| `LoginGraceTime` | 20 | Reduce login timeout (down from 2m) |
| `ClientAliveInterval` | 60 | Send keepalive every 60 seconds |
| `ClientAliveCountMax` | 3 | Drop after 3 missed keepalives |

**Dotbot linking:** `/etc/ssh/sshd_config` → `system/ssh/sshd_config` (with sudo)

---

## SSH Agent Configuration

The SSH agent is configured in `shell/zsh/zprofile`:

- **Persistent socket:** `~/.ssh/ssh_auth_sock`
- **Auto-start:** Agent starts on login if not running
- **Auto-load keys:** Keys are automatically loaded from macOS Keychain
- **macOS Keychain:** Keys are registered with `--apple-use-keychain` for Touch ID support

### Machine-Specific Keys

Keys are loaded based on hostname:
- **All machines:** `id_personal`
- **Mac-WD77LWRW (work machine):** `id_personal` + `id_work`

---

## Key Passphrase Protection

All SSH private keys (`~/.ssh/id_personal`, etc.) are passphrase-protected. On macOS, the passphrase is stored in Keychain, allowing Touch ID authentication.

### Adding/Changing Passphrase (Non-Interactive)

To add or change a passphrase on a remote host without interactive prompts:

```bash
# Define the new passphrase securely
NEW_PASS="your-secure-passphrase"

# Update passphrase via SSH (non-interactive)
ssh <hostname> bash -lc 'umask 077; \
  read -r old <&3; read -r new1 <&3; read -r new2 <&3; \
  [[ "$new1" == "$new2" ]] || { echo "Mismatch" >&2; exit 1; }; \
  ssh-keygen -p -P "$old" -N "$new1" -f ~/.ssh/id_personal' \
  3<<<"$'\n'$NEW_PASS$'\n'$NEW_PASS"
```

**Security note:** Never log passphrases. Use process substitution or here-strings to avoid command-line visibility.

### Registering with macOS Keychain

After adding a passphrase, register the key with Keychain for Touch ID:

```bash
ssh <hostname> 'ssh-add --apple-use-keychain ~/.ssh/id_personal'
```

You'll be prompted for the passphrase once, then Touch ID will work for future authentications.

### Verifying Key Status

```bash
ssh <hostname> 'ssh-add -l'
```

Should show your key fingerprint and comment.

---

## Deployment

### Initial Setup (New Machine)

1. **Clone dotfiles:**
   ```bash
   git clone https://github.com/stefmf/.dotfiles.git ~/.dotfiles
   cd ~/.dotfiles
   ```

2. **Run Dotbot installer:**
   ```bash
   ./install
   ```
   
   This will:
   - Link SSH client config to `~/.ssh/config`
   - Link SSH server config to `/etc/ssh/sshd_config` (requires sudo)
   - Create required directories

3. **Verify sshd syntax:**
   ```bash
   sudo sshd -t
   ```
   
   Should exit silently (no output = success).

4. **Test key authentication locally:**
   ```bash
   ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no localhost 'true'
   ```
   
   Should succeed without password prompt.

5. **Reload sshd:**
   ```bash
   # macOS:
   sudo launchctl kickstart -k system/com.openssh.sshd
   
   # Linux (systemd):
   sudo systemctl reload sshd
   ```

6. **Add passphrase to key** (if not already set):
   ```bash
   ssh-keygen -p -f ~/.ssh/id_personal
   ```

7. **Register with Keychain** (macOS only):
   ```bash
   ssh-add --apple-use-keychain ~/.ssh/id_personal
   ```

### Updating Existing Machine

```bash
cd ~/.dotfiles
git pull
./install
sudo sshd -t  # Verify syntax
sudo launchctl kickstart -k system/com.openssh.sshd  # Reload sshd
```

---

## Authorized Keys Management

Ensure your public key is in `~/.ssh/authorized_keys` on each host:

```bash
# Check if key exists
grep -q "$(cat ~/.ssh/id_personal.pub)" ~/.ssh/authorized_keys || \
  cat ~/.ssh/id_personal.pub >> ~/.ssh/authorized_keys

# Set proper permissions
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

---

## Troubleshooting

### Cannot SSH into machine after changes

**Symptoms:** Connection refused or "Permission denied (publickey)"

**Diagnosis:**
1. Check sshd syntax: `sudo sshd -t`
2. Check sshd logs: `sudo tail -f /var/log/system.log | grep sshd` (macOS)
3. Verify key in authorized_keys: `cat ~/.ssh/authorized_keys`
4. Verify key loaded in agent: `ssh-add -l`
5. Test with verbose output: `ssh -vvv <hostname>`

**Common Issues:**
- **Wrong permissions:** `~/.ssh` must be 700, private keys must be 600, `authorized_keys` must be 600 or 644
- **Key not loaded:** Run `ssh-add --apple-use-keychain ~/.ssh/id_personal`
- **Wrong key:** Ensure `authorized_keys` contains the matching public key
- **sshd not reloaded:** Run `sudo launchctl kickstart -k system/com.openssh.sshd`

### Locked out of remote machine

**Emergency Access:**

If you have physical access or console access:

1. **Restore default sshd_config:**
   ```bash
   sudo rm /etc/ssh/sshd_config
   sudo cp /etc/ssh/sshd_config.default /etc/ssh/sshd_config  # If backup exists
   # Or reinstall openssh package
   ```

2. **Temporarily enable password auth:**
   ```bash
   sudo nano /etc/ssh/sshd_config
   # Set: PasswordAuthentication yes
   sudo launchctl kickstart -k system/com.openssh.sshd
   ```

3. **Fix authorized_keys and retry key auth**

**Prevention:** Always test key auth from a second connection before reloading sshd.

---

## Rollback Instructions

### Via Dotbot (Recommended)

1. **Revert repo changes:**
   ```bash
   cd ~/.dotfiles
   git revert <commit-hash>
   ./install
   ```

2. **Reload sshd:**
   ```bash
   sudo launchctl kickstart -k system/com.openssh.sshd
   ```

### Manual Rollback

1. **Remove symlink:**
   ```bash
   sudo rm /etc/ssh/sshd_config
   ```

2. **Restore system default:**
   ```bash
   # macOS: Reinstall OpenSSH or restore from Time Machine
   # Linux: Restore from package manager or /etc/ssh/sshd_config.dpkg-old
   sudo apt-get install --reinstall openssh-server  # Debian/Ubuntu
   ```

3. **Reload sshd**

---

## Security Best Practices

1. ✅ **Use strong passphrases** - 20+ characters, random
2. ✅ **Rotate keys periodically** - generate new keys every 1-2 years
3. ✅ **Audit authorized_keys** - remove old/unused keys
4. ✅ **Monitor SSH logs** - watch for failed auth attempts
5. ✅ **Use unique keys per machine** - consider separate keys for work/personal
6. ✅ **Backup private keys securely** - encrypted backup in password manager
7. ✅ **Disable SSH on unused machines** - reduce attack surface

---

## Platform-Specific Notes

### macOS

- **Keychain integration:** `UseKeychain yes` and `--apple-use-keychain` flag
- **Touch ID support:** Requires passphrase stored in Keychain
- **sshd reload:** `sudo launchctl kickstart -k system/com.openssh.sshd`
- **Logs:** `/var/log/system.log` (filter for `sshd`)

### Linux

- **No Keychain:** Use `ssh-agent` or `gnome-keyring` for passphrase caching
- **sshd reload:** `sudo systemctl reload sshd` or `sudo service sshd reload`
- **Logs:** `/var/log/auth.log` (Debian/Ubuntu) or `journalctl -u sshd`

---

## Additional Resources

- [OpenSSH Manual](https://www.openssh.com/manual.html)
- [SSH Key Management Best Practices](https://www.ssh.com/academy/ssh/key-management)
- [Hardening SSH](https://www.ssh-audit.com/)
- [macOS Touch ID for sudo](https://sixcolors.com/post/2020/11/quick-tip-enable-touch-id-for-sudo/)

---

## Change Log

- **2025-10-04:** Initial implementation - enforced key-only authentication across all personal machines
