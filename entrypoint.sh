#!/bin/bash

# Set environment variable
echo "::set-output name=kernel-version::$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+')"

# Download the latest kernel source RPM
koji download-build --arch=src kernel-"$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+')".fc34.src.rpm

# Install the latest kernel source RPM
rpm -Uvh kernel-"$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+')".fc34.src.rpm

# Install the build dependencies
cd ~/rpmbuild/SPECS/ && dnf builddep kernel.spec

# Download the ACS override patch
curl -o ~/rpmbuild/SOURCES/add-acs-override.patch https://raw.githubusercontent.com/some-natalie/fedora-acs-override/main/acs/add-acs-override.patch 

# Edit the spec file with some sed magics
sed -i 's/# define buildid .local/%define buildid .acs/g' ~/rpmbuild/SPECS/kernel.spec
sed -i '/^Patch1:*/a Patch1000: add-acs-override.patch' ~/rpmbuild/SPECS/kernel.spec
sed -i '/^ApplyOptionalPatch patch-*/a ApplyOptionalPatch add-acs-override.patch' ~/rpmbuild/SPECS/kernel.spec

# Build the things!
cd ~/rpmbuild/SPECS && rpmbuild -bb kernel.spec --without debug --without debuginfo
