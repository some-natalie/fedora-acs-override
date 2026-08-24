#!/bin/bash

# Set environment variable
echo "kernel-version=$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+')" >>"$GITHUB_OUTPUT"

# Download the latest kernel source RPM
koji download-build --arch=src kernel-"$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+.fc[0-9][0-9]')".src.rpm

# Install the latest kernel source RPM
rpm -Uvh kernel-"$(dnf list kernel | grep -Eo '[0-9]\.[0-9]+\.[0-9]+-[0-9]+.fc[0-9][0-9]')".src.rpm

# Install the build dependencies
cd ~/rpmbuild/SPECS/ && dnf builddep kernel.spec -y

# Download the ACS override patch
curl -o ~/rpmbuild/SOURCES/add-acs-override.patch https://raw.githubusercontent.com/some-natalie/fedora-acs-override/main/acs/add-acs-override.patch

# Edit the spec file with some sed magics
# Rename the whole family to kernel-acs - every subpackage is named off %{name}.
# Sharing Fedora's names doesn't just risk confusion, it can't win: the .acs
# buildid lands before %{?dist}, so rpm reads 200.acs.fc44 as older than 200.fc44.
sed -i 's/^%global package_name kernel$/%global package_name kernel-acs/' ~/rpmbuild/SPECS/kernel.spec
if ! grep -q '^%global package_name kernel-acs$' ~/rpmbuild/SPECS/kernel.spec; then
  echo "::error::could not rename package_name, kernel.spec layout changed"
  exit 1
fi
sed -i 's/# define buildid .local/%define buildid .acs/g' ~/rpmbuild/SPECS/kernel.spec
sed -i '/^Patch1:*/a Patch1000: add-acs-override.patch' ~/rpmbuild/SPECS/kernel.spec
sed -i '/^ApplyOptionalPatch patch-*/a ApplyOptionalPatch add-acs-override.patch' ~/rpmbuild/SPECS/kernel.spec
sed -i 's|cp ./bpf/tools/sbin/bpftool %{buildroot}%{_libexecdir}/kselftests/bpf/bpftool|cp /usr/bin/bpftool %{buildroot}%{_libexecdir}/kselftests/bpf/bpftool|' ~/rpmbuild/SPECS/kernel.spec

# %prep checks each patch is declared by grepping ${RPM_PACKAGE_NAME}.spec, so
# the file has to follow the package rename or it rejects the ACS patch as
# undeclared. It hides the missing-file error, so the message blames the patch.
mv ~/rpmbuild/SPECS/kernel.spec ~/rpmbuild/SPECS/kernel-acs.spec

# The config and changelog sources are named off %{name} too, so they follow the
# rename as well - %prep copies them by glob and fails if none match.
cd ~/rpmbuild/SOURCES || exit 1
for f in kernel-*.config kernel.changelog; do
  [ -e "$f" ] && mv "$f" "kernel-acs${f#kernel}"
done

# Build the things!
# perf, libperf and tools are dropped because they're named absolutely
# (%package -n perf) rather than off %{name}, so the rename misses them and they
# would collide with Fedora's. rtla and rv are inside the tools conditional.
cd ~/rpmbuild/SPECS && rpmbuild -bb kernel-acs.spec --without debug --without debuginfo \
  --without perf --without libperf --without tools --target x86_64 --nodeps
