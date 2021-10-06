# Notes

Here are various notes and such that don't belong in the README but don't have a home anywhere else.

## Kernel 5.14.x notes

In Fedora 34, as of kernel 5.14.x, [Intel TSX](https://en.wikipedia.org/wiki/Transactional_Synchronization_Extensions) (transactional synchronization extensions) is disabled on more CPUs for security reasons.  You can read up more on the security implications [here](https://www.phoronix.com/scan.php?page=news_item&px=Intel-TSX-Off-New-Microcode).

If your VM fails to launch with some variety of the message `Host CPU does not provide required features: rtm, hle`, but only after moving from kernel 5.13.x to 5.14.x, there's a good chance you have an effected CPU.  The two things libvirt is complaining about are dependent on TSX - Restricted Transactional Memory (RTM) and Hardware Lock Elision (HLE).

To verify TSX is disabled, run the command below:

```shell
$ lscpu | grep Tsx
Vulnerability Tsx async abort:   Mitigation; TSX disabled
```

To mitigate it, I disabled these features in the VM to match the host.  Add the two `feature policy` lines, as shown below, to the XML file defining your virtual machine for libvirt in the CPU section:

```xml
<cpu mode="custom" match="exact" check="partial">
  <model fallback="allow">Skylake-Client</model>
  <topology sockets="1" dies="1" cores="4" threads="1"/>
  <feature policy="disable" name="rtm"/>
  <feature policy="disable" name="hle"/>
</cpu>
```
