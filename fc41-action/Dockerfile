FROM fedora:41@sha256:308f23de6b836224f523b3b27055479a1653faf923bf4cb8e14b1e0c80a7cd94

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
    perl-generators python3-devel which kernel-rpm-macros \
    && dnf clean all

# Setup build directory
RUN rpmdev-setuptree

# Set up the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
