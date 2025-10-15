FROM fedora:41@sha256:c3643bda846169b342b400d4bbd1cb7022a7037e108b403a97305d1cb1644bcd

# Add RPM Fusion
RUN dnf install -y \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm \
  && dnf clean all

# Update
RUN dnf update -y && dnf clean all

# Install build dependencies
RUN dnf install -y fedpkg fedora-packager rpmdevtools ncurses-devel pesign \
  bpftool bc bison dwarves elfutils-devel flex gcc gcc-c++ gcc-plugin-devel \
  glibc-static hostname m4 make net-tools openssl openssl-devel perl-devel \
  perl-generators python3-devel which kernel-rpm-macros kernel-tools \
  kernel-tools-libs-devel \
  && dnf clean all

# Setup build directory
RUN rpmdev-setuptree

# Set up the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
