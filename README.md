# PodOS

## Customization

### User

```dockerfile
ARG SSH_USER=user
ARG SSH_PUBKEY_FILE=authorized_keys

RUN useradd --uid 1000 --home-dir /var/home/${SSH_USER} --no-create-home --shell /usr/bin/bash ${SSH_USER}

COPY <<EOF /usr/lib/tmpfiles.d/99-${SSH_USER}.conf
d /var/home/${SSH_USER} 0700 ${SSH_USER} ${SSH_USER} - -
z /var/home/${SSH_USER} 0700 ${SSH_USER} ${SSH_USER} - -
EOF

ADD --chmod=644 ${SSH_PUBKEY_FILE} /usr/share/ssh/keys/${SSH_USER}.authorized_keys
```

### Sudo

```dockerfile
ARG SSH_USER=user

COPY --chmod=440 <<EOF /etc/sudoers.d/99-${SSH_USER}
${SSH_USER} ALL=(ALL) NOPASSWD: ALL
EOF
```

## Install

- [Installing on Bare Metal](https://docs.fedoraproject.org/en-US/bootc/bare-metal/)
- [Installing on generic infrastructure](https://docs.fedoraproject.org/en-US/bootc/provisioning-generic/)
