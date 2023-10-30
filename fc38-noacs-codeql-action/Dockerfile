FROM fedora:38

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

# Setup CodeQL
ENV CODEQL_HOME /usr/local/codeql-home
RUN mkdir -p ${CODEQL_HOME}

RUN wget -O codeql-bundle.tar.gz https://github.com/github/codeql-action/releases/download/codeql-bundle-v2.15.1/codeql-bundle-linux64.tar.gz &&\
    tar -xvzf codeql-bundle.tar.gz &&\
    cp -R ./codeql ${CODEQL_HOME}

ENV PATH="${CODEQL_HOME}/codeql:${PATH}"

# Set up the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
