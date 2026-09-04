# GnuPG configuration examples

These files are templates, not a Stow-managed `~/.gnupg` path. Copy them only
when you want the SSH agent and cache behavior described below:

```sh
umask 077
install -d -m 700 ~/.gnupg
install -m 600 gpg-agent.conf ~/.gnupg/gpg-agent.conf
install -m 600 gpg.conf ~/.gnupg/gpg.conf
gpgconf --kill gpg-agent
```

`gpg-agent` starts lazily on the next GnuPG, SSH, or interactive Zsh request.
After it starts, list the SSH-compatible public keys with `ssh-add -L`.

To let `gpg-agent` manage an OpenPGP authentication key (not needed for a
YubiKey/smartcard auth key, which gpg-agent exposes automatically), obtain its
keygrip with `gpg --list-keys --with-keygrip` — only the authentication-capable
(`[A]`) subkey's grip belongs here — then append it to `~/.gnupg/sshcontrol`
with `echo KEYGRIP >> ~/.gnupg/sshcontrol`.

When a host has access to many keys, use SSH `IdentitiesOnly yes` plus an
explicit `IdentityFile` or `IdentityAgent` entry so authentication does not
iterate every available key.
