ARG KERNEL_VERSION=0.0.0-invalid.fc00.x86_64
FROM ghcr.io/ublue-os/akmods-nvidia-open:main-44-${KERNEL_VERSION} AS akmods

FROM ghcr.io/mikucat0309/podos:latest

RUN --mount=type=bind,from=akmods,src=/rpms,dst=/akmods <<EORUN
set -exuo pipefail
dnf install -y /akmods/ublue-os/ublue-os-nvidia-addons-*.rpm

sed -i 's/^enabled=0/enabled=1/' /etc/yum.repos.d/negativo17-fedora-nvidia.repo \
  /etc/yum.repos.d/nvidia-container-toolkit.repo

dnf install -y \
  /akmods/kmods/kmod-nvidia-*.x86_64.rpm \
  /akmods/nvidia/nvidia-driver-cuda-*.x86_64.rpm \
  /akmods/nvidia/nvidia-driver-common-*.x86_64.rpm \
  /akmods/nvidia/nvidia-kmod-common-*.noarch.rpm \
  /akmods/nvidia/nvidia-modprobe-*.x86_64.rpm \
  /akmods/nvidia/nvidia-persistenced-*.x86_64.rpm \
  nvidia-container-toolkit-base

sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/negativo17-fedora-nvidia.repo \
  /etc/yum.repos.d/nvidia-container-toolkit.repo
dnf clean all
rm -rf /var/cache/* /var/lib/dnf /var/log/dnf5.log /run/dnf /run/selinux-policy
EORUN

RUN <<EORUN
set -x
if [ -f /usr/share/selinux/packages/targeted/nvidia-driver.pp.bz2 ]; then
  semodule --install /usr/share/selinux/packages/targeted/nvidia-driver.pp.bz2 || true
fi
semodule --install /usr/share/selinux/packages/nvidia-container.pp || true
EORUN

RUN bootc container lint
