# Fedora 33 + PCI passthrough


### Prerequisites
- Fedora 33 (fresh install off the live USB image)
- Computer with
  - Two graphics cards
  - Motherboard with the Intel 200 series chipset (Union Point) or newer
- A fresh backup of anything you don't care to lose

:information_source:  The two graphics cards can be different models.  If your cards are identical, you'll need to do some extra steps that are prefaced with (ACS only).  These steps include compiling your own kernel to include Alex Williamson's patch to allow any PCIe device to use Access Control Services.  More information on this patch, why it's necessary, and what it does available [here](https://lkml.org/lkml/2013/5/30/513).  If your cards aren't identical, skip these steps.


### Setup and configuration of the host machine
1. Add RPM Fusion
    ```
    sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    ```

1. (ACS only) - Install the dependencies to start building your own kernel.
    ```shell
    sudo dnf install fedpkg fedora-packager rpmdevtools ncurses-devel pesign rpmtools
    ```

1. (ACS only) - Set up your home build directory (if you haven't ever built any RPMs before)
    ```shell
    rpmdev-setuptree
    ```

1. (ACS only) - Install the kernel source and finish installing dependencies.
    ```shell
    koji download-build --arch=src kernel-4.18.5-200.fc28
    rpm -Uvh kernel-4.18.5-200.fc28.src.rpm
    cd rpmbuild/SPECS/
    sudo dnf builddep kernel.spec
    ```

1. (ACS only) - Add the ACS patch ([link](acs/add-acs-override.patch)) as `~/rpmbuild/SOURCES/add-acs-override.patch`.
    ```shell
    curl -o ~/rpmbuild/SOURCES/add-acs-override.patch https://raw.githubusercontent.com/Somersall-Natalie/fedora-acs-override/master/acs/add-acs-override.patch    
    ```

1. (ACS only) - Edit `~/rpmbuild/SPECS/kernel.spec` to set the build ID and add the patch.  Since each release of the spec file could change, it's not much help giving line numbers, but both of these should be near the top of the file.  To set the build id, add the two lines near the top of the spec file with the other release information.
    ```
    # Set buildid
    %define buildid .acs
    ```

    To add the patch, add the two lines below to the spec file in the section for patches (usually right below the sources).
    ```
    # ACS override patch
    Patch1000: add-acs-override.patch
    ```

    Then tell it to apply the patch in the `prep` section.
    ```
    ApplyOptionalPatch add-acs-overrides.patch
    ```

1. (ACS only) - Compile!  This takes a [long time](https://xkcd.com/303/).
    ```shell
    rpmbuild -bb kernel.spec
    ```

1. (ACS only) - Install the new packages!
    ```shell
    cd ~/rpmbuild/RPMS/x86_64
    sudo dnf update *.rpm
    ```

    :information_source:  You should now have at least the following packages installed:  `kernel`, `kernel-core`, `kernel-devel`, `kernel-modules`, and `kernel-modules-extra`.

1. Update and reboot
    ```shell
    sudo dnf clean all
    sudo dnf update -y
    sudo reboot
    ```

1. Install virtualization software and add yourself to the user group
    ```shell
    sudo dnf install @virtualization
    sudo usermod -G libvirt -a $(whoami)
    sudo usermod -G kvm -a $(whoami)
    ```

1. Install (proprietary) nVidia drivers and remove/blacklist (open source) nouveau drivers.
    ```shell
    sudo su -
    dnf install xorg-x11-drv-nvidia akmod-nvidia "kernel-devel-uname-r == $(uname -r)" xorg-x11-drv-nvidia-cuda vulkan vdpauinfo libva-vdpau-driver libva-utils
    dnf remove *nouveau*
    echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
    ```

1. Reboot again!
    ```shell
    sudo reboot
    ```

1. Verify that the nVidia drivers are installed correctly.
    ```shell
    lsmod | grep nouveau   # This should display nothing
    lsmod | grep nvidia    # This should display at least a couple things
    ```

1. Edit `/etc/default/grub` to enable IOMMU, blacklist nouveau, and load vfio-pci first.

    If your video cards are different:
    ```
    GRUB_CMDLINE_LINUX="rd.driver.pre=vfio-pci rd.driver.blacklist=nouveau modprobe.blacklist=nouveau rd.lvm.lv=fedora/root rd.lvm.lv=fedora/swap rhgb quiet intel_iommu=on iommu=pt"
    ```

    If your video cards are identical, use this instead:
    ```
    GRUB_CMDLINE_LINUX="rd.driver.pre=vfio-pci rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1 resume=/dev/mapper/arch-swap rd.lvm.lv=arch/root rd.lvm.lv=arch/swap rhgb quiet intel_iommu=on iommu=pt pcie_acs_override=downstream"
    ```

1. Rebuild GRUB's configuration
    ```shell
    sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
    ```

1. Edit `/etc/modprobe.d/kvm.conf`.  These two lines are edited out due to stability concerns.  YMMV.
    ```
    #options kvm_intel nested=1
    #options kvm_amd nested=1
    ```

1. Create or edit `/etc/modprobe.d/local.conf`, adding the line below:
    ```
    install vfio-pci /sbin/vfio-pci-override.sh
    ```

1. Create or edit `/etc/dracut.conf.d/local.conf`, adding the line below:
    ```
    add_drivers+= " vfio vfio_iommu_type1 vfio_pci vfio_virqfd "
    install_items+=" /sbin/vfio-pci-override.sh /usr/bin/find /usr/bin/dirname "
    ```

1. Create a file `/sbin/vfio-pci-override.sh` with permissions `755` (file in this directory of the repo).

1. Rebuild using `dracut`
    ```shell
    sudo dracut -f --kver `uname -r`
    ```

1. Reboot again!

1. Verify that your target hardware is using `vfio-pci` as the driver.  Omit the `-s 00:02:00` on another machine to get the entire output, as this argument narrows the output down to the device specified.
    ```shell
    nataliepc /h/n/k/kernel $ lspci -vv -n -s 00:02:00
    02:00.0 0300: 10de:1c82 (rev a1) (prog-if 00 [VGA controller])
      Subsystem: 3842:6251
      Control: I/O- Mem- BusMaster- SpecCycle- MemWINV- VGASnoop- ParErr- Stepping- SERR- FastB2B- DisINTx-
      Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR- <PERR- INTx-
      Interrupt: pin A routed to IRQ 10
      Region 0: Memory at dc000000 (32-bit, non-prefetchable) [disabled] [size=16M]
      Region 1: Memory at a0000000 (64-bit, prefetchable) [disabled] [size=256M]
      Region 3: Memory at b0000000 (64-bit, prefetchable) [disabled] [size=32M]
      Region 5: I/O ports at d000 [disabled] [size=128]
      Expansion ROM at dd000000 [disabled] [size=512K]
      Capabilities: <access denied>
      Kernel driver in use: vfio-pci
      Kernel modules: nouveau, nvidia_drm, nvidia

    02:00.1 0403: 10de:0fb9 (rev a1)
      Subsystem: 3842:6251
      Control: I/O- Mem- BusMaster- SpecCycle- MemWINV- VGASnoop- ParErr- Stepping- SERR- FastB2B- DisINTx-
      Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR- <PERR- INTx-
      Interrupt: pin B routed to IRQ 11
      Region 0: Memory at dd080000 (32-bit, non-prefetchable) [disabled] [size=16K]
      Capabilities: <access denied>
      Kernel driver in use: vfio-pci
      Kernel modules: snd_hda_intel
    ```

1. Proceed to set up your virtual machine.


### Resources
- Alex Williamson's blog on the VFIO tips and tricks - [link](https://vfio.blogspot.com/)
- Arch Linux wiki post on PCI passthrough -  [link](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF)


### Disclaimer
I put this together based on my own machine at home because I knew I'd forget this process if I ever had to do it again.  There was a lot of reading of Bugzilla, StackOverflow, and a bunch of blogs/forums/mailing lists all over the internet.  Thanks to everyone who did something similar so I could cobble together something from all of them that Works On My Machine.  This is by no means the only way to solve the problem.  :)
