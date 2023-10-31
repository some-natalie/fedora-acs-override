#!/bin/bash

# Set environment variable
echo "kernel-version=$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+')" >> $GITHUB_OUTPUT

# Download the latest kernel source RPM
koji download-build --arch=src kernel-"$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+.fc[0-9][0-9]')".src.rpm

# Install the latest kernel source RPM
rpm -Uvh kernel-"$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+.fc[0-9][0-9]')".src.rpm

# Install the build dependencies
cd ~/rpmbuild/SPECS/ && dnf builddep kernel.spec -y

# Download the ACS override patch
curl -o ~/rpmbuild/SOURCES/add-acs-override.patch https://raw.githubusercontent.com/some-natalie/fedora-acs-override/main/acs/add-acs-override.patch 

# Edit the spec file with some sed magics
sed -i 's/# define buildid .local/%define buildid .acs/g' ~/rpmbuild/SPECS/kernel.spec
sed -i '/^Patch1:*/a Patch1000: add-acs-override.patch' ~/rpmbuild/SPECS/kernel.spec
sed -i '/^ApplyOptionalPatch patch-*/a ApplyOptionalPatch add-acs-override.patch' ~/rpmbuild/SPECS/kernel.spec

# Setup CodeQL
codeql resolve languages
codeql resolve qlpacks

# Build and scan the things!
cd ~/rpmbuild/SPECS &&\
  codeql database create cpp-database --language=cpp --threads=62 --ram=250000 \
  --command 'rpmbuild -bb kernel.spec --without debug --without debuginfo --target x86_64 --nodeps'

# Analyze the things
codeql database analyze ~/rpmbuild/SPECS/cpp-database --threads=62 --ram=250000 \
  --format=sarif-latest --output=~/rpmbuild/SPECS/cpp-results.sarif
