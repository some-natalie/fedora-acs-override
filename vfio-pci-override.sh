#!/bin/sh

# This script overrides the default driver to be the vfio-pci driver (similar
# to the pci-stub driver) for the devices listed.  In this case, it only uses
# two devices that both belong to one nVidia graphics card (graphics, audio).

# Located at /sbin/vfio-pci-override.sh

DEVS="0000:02:00.0 0000:02:00.1"

if [ ! -z "$(ls -A /sys/class/iommu)" ] ; then
  for DEV in $DEVS; do
    echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
  done
fi

modprobe -i vfio-pci
