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
PATH=$PATH:/usr/local/codeql-home/codeql
codeql resolve languages
codeql resolve qlpacks

# Build and scan the things!
cd ~/rpmbuild/SPECS &&\
  codeql database create c-cpp-database --language=c-cpp \
  --command 'rpmbuild -bb kernel.spec --without debug --without debuginfo --target x86_64 --nodeps'

# Analyze the things
codeql database analyze ~/rpmbuild/SPECS/c-cpp-database --format=sarif-latest --output=/workspace/source/c-cpp-results.sarif
