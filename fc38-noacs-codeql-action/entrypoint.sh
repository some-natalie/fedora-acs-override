#!/bin/bash

# Set environment variable
echo "kernel-version=$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+')" >> $GITHUB_OUTPUT

# Download the latest kernel source RPM
koji download-build --arch=src kernel-"$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+.fc[0-9][0-9]')".src.rpm

# Install the latest kernel source RPM
rpm -Uvh kernel-"$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+.fc[0-9][0-9]')".src.rpm

# Install the build dependencies
cd ~/rpmbuild/SPECS/ && dnf builddep kernel.spec -y

# Setup CodeQL
codeql resolve languages
codeql resolve qlpacks

# Build and scan the things!
cd ~/rpmbuild/SPECS &&\
  codeql database create cpp-database --language=cpp --threads=62 --ram=250000 \
  --command 'rpmbuild -bb kernel.spec --without debug --without debuginfo --target x86_64 --nodeps'

# Analyze the things
codeql database analyze ~/rpmbuild/SPECS/cpp-database --threads=62 --ram=250000 \
  --format=sarif-latest --output=/workspace/source/cpp-results.sarif
