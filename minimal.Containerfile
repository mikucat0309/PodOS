FROM quay.io/bootc-devel/fedora-bootc-44-minimal:latest

ARG SSH_USER=user
ARG SSH_PUBKEY_FILE=authorized_keys

COPY <<EOF /etc/dnf/dnf.conf
[main]
tsflags=nodocs
install_weak_deps=False
EOF

RUN <<EORUN
set -exuo pipefail
dnf install -y shadow-utils sudo systemd-networkd systemd-resolved cloud-init cloud-utils-growpart \
  iproute openssh-server podman
dnf clean all
rm -rf /var/cache/* /var/lib/dnf /var/log/dnf5.log /run/dnf /run/cloud-init
EORUN

# -------- VM --------

RUN mkdir -p /usr/lib/bootc/kargs.d /usr/lib/issue.d
COPY <<EOF /usr/lib/bootc/kargs.d/99-console.toml
kargs = ["console=tty0", "console=ttyS0,115200"]
EOF

COPY <<'EOF' /usr/lib/issue.d/99-bootc.issue
\S{PRETTY_NAME} \r (\l)
Current IP: \4 \6
EOF

# -------- Bootc --------

COPY <<EOF /usr/lib/composefs/setup-root-conf.toml
[etc]
mount = "transient"
EOF

# -------- Growpart --------

RUN install -m 755 /usr/share/doc/bootc-base-imagectl/manifests/standard/bootc-generic-growpart /usr/libexec/bootc-generic-growpart
COPY <<'EOF' /usr/lib/systemd/system/bootc-generic-growpart.service
[Unit]
Description=Bootc Fallback Root Filesystem Grow
Documentation=https://gitlab.com/fedora/bootc/docs
# This helps verify that we're running in a bootc/ostree based target.
ConditionPathIsMountPoint=/sysroot
# For someone making a smaller image, assume they have this handled.
ConditionPathExists=/usr/bin/growpart
# We want to run before any e.g. large container images might be pulled.
DefaultDependencies=no
Requires=sysinit.target
After=sysinit.target
Before=basic.target

[Service]
ExecStart=/usr/libexec/bootc-generic-growpart
# So we can temporarily remount the sysroot writable
MountFlags=slave
# Just to auto-cleanup our temporary files
PrivateTmp=yes
EOF

RUN mkdir -p /usr/lib/systemd/system/local-fs.target.wants
RUN ln -s /usr/lib/systemd/system/bootc-generic-growpart.service /usr/lib/systemd/system/local-fs.target.wants/bootc-generic-growpart.service

# -------- Cloud-init --------

COPY <<EOF /etc/cloud/cloud.cfg.d/99-bootc.cfg
ssh_deletekeys: false
ssh_genkeytypes: []
growpart:
  mode: off
resize_rootfs: false
EOF

COPY <<EOF /usr/lib/tmpfiles.d/99-cloud-init-dirs.conf
d /var/lib/cloud 0755 root root - -
EOF

RUN rm /usr/lib/systemd/system/sshd-keygen@.service.d/disable-sshd-keygen-if-cloud-init-active.conf

# -------- NTP --------

RUN systemctl enable systemd-timesyncd.service

# -------- SSH --------

RUN install -d -m 0755 /etc/ssh/sshd_config.d
RUN install -d -m 0755 /usr/share/ssh/keys
COPY <<EOF /etc/ssh/sshd_config.d/99-bootc.conf
PermitRootLogin no
PasswordAuthentication no
HostKey /var/lib/ssh/hostkeys/ssh_host_rsa_key
HostKey /var/lib/ssh/hostkeys/ssh_host_ecdsa_key
HostKey /var/lib/ssh/hostkeys/ssh_host_ed25519_key
AuthorizedKeysFile /usr/share/ssh/keys/%u.authorized_keys
EOF

COPY <<EOF /etc/systemd/system/sshd-keygen@.service.d/99-bootc.conf
[Unit]
ConditionPathExists=!/var/lib/ssh/hostkeys/ssh_host_%i_key

[Service]
ExecStart=
ExecStart=/usr/bin/ssh-keygen -q -t %i -f /var/lib/ssh/hostkeys/ssh_host_%i_key -C '' -N ''
EOF

COPY <<EOF /etc/selinux/targeted/contexts/files/file_contexts.local
/var/lib/ssh/hostkeys(/.*)?   system_u:object_r:ssh_home_t:s0
/usr/share/ssh/keys(/.*)?   system_u:object_r:ssh_home_t:s0
EOF

COPY <<EOF /usr/lib/tmpfiles.d/99-ssh-dirs.conf
d /var/db/sudo 0700 root root - -
d /var/db/sudo/lectured 0700 root root - -
d /var/lib/ssh 0755 root root - -
d /var/lib/ssh/hostkeys 0750 root root - -
EOF

# -------- User --------

COPY <<EOF /usr/lib/sysusers.d/99-${SSH_USER}.conf
u ${SSH_USER} - - /var/home/${SSH_USER} /usr/bin/bash
m ${SSH_USER} wheel
EOF

COPY --chmod=440 <<EOF /etc/sudoers.d/99-${SSH_USER}
${SSH_USER} ALL=(ALL) NOPASSWD: ALL
EOF

COPY <<EOF /usr/lib/tmpfiles.d/99-${SSH_USER}.conf
d /var/home/${SSH_USER} 0700 ${SSH_USER} ${SSH_USER} - -
z /var/home/${SSH_USER} 0700 ${SSH_USER} ${SSH_USER} - -
EOF

ADD --chmod=644 ${SSH_PUBKEY_FILE} /usr/share/ssh/keys/${SSH_USER}.authorized_keys

# -------- Cleanup --------

RUN find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name en ! -name en_US -exec rm -rf {} +
RUN rm -rf /usr/share/{man,info,doc,licenses}

RUN bootc container lint
LABEL containers.bootc=1
LABEL ostree.bootable=1
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
