# Contributing

## Developer Setup

Run the `devtools` module from `setup.sh`:

```bash
bash ~/setup.sh
```

Select **Dev tools** from the module list. This will:

1. Prompt for your name, email, and GPG key expiry
2. Generate a GPG signing key and SSH ed25519 key
3. Store both passphrases in the GNOME Keyring
4. Authenticate with GitHub CLI (`gh auth login`)
5. Upload the GPG key and SSH key to your GitHub account
6. Configure git identity and commit signing globally
7. Install Claude Code and Zed editor

After completion, commits will be GPG-signed automatically.
