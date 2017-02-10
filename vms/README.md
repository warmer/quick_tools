# Virtualization Tools and Notes

To enable PCI passthrough, both your motherboard and CPU must support VT-d.

You must also enable the iommu boot-time parameter, and the host OS must be
configured to explicitly not use the PCI devices that you wish to make
available to guests.

## Configuring PCI devices for passthrough

First, I blacklist the PCIe GPU driver so that my host OS doesn't attempt to
load it at boot time by adding `blacklist radeon` to
`/etc/modprobe.d/blacklist.conf`. Note that this step may vary depending on
the drivers and hardware of your system.

Then, I enable the kernel parameters necessary to enable passthrough at
boot-time. You may need to check that your kernel supports these parameters.

(Note: don't forget to run `update-grub` after editing the grub entry.)

Here is an example of the grub entry on my machine (`/etc/default/grub`):

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on iommu=1 pci-stub.ids=1002:9442,1002:aa30,8086:105e"
```

Where do you find the `pci-stub.ids`?

```
lspci -vnn
```

On my machine, my video card has two entries, so I must add both. Here's what I
see when I run `lspci -vnn`:

```
01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] RV770 [Radeon HD 4850] [1002:9442] (prog-if 00 [VGA controller])
  Subsystem: Gigabyte Technology Co., Ltd Device [1458:21c7]
  Flags: fast devsel, IRQ 16
  Memory at d0000000 (64-bit, prefetchable) [disabled] [size=256M]
  Memory at efd20000 (64-bit, non-prefetchable) [disabled] [size=64K]
  I/O ports at e000 [disabled] [size=256]
  Expansion ROM at efd00000 [disabled] [size=128K]
  Capabilities: <access denied>
  Kernel driver in use: vfio-pci

01:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] RV770 HDMI Audio [Radeon HD 4850/4870] [1002:aa30]
  Subsystem: Gigabyte Technology Co., Ltd Device [1458:aa30]
  Flags: fast devsel, IRQ 17
  Memory at efd30000 (64-bit, non-prefetchable) [disabled] [size=16K]
  Capabilities: <access denied>
  Kernel driver in use: vfio-pci
```

## Associating the vfio-pci Drivers

Once your machine has been started with the right kernel options, you must
assign the VFIO driver for all pass-through devices to enable guests to manage
them.

You may need to unbind existing drivers first:

```
echo '0000:01:00.1' | sudo tee /sys/bus/pci/devices/0000:01:00.1/driver/unbind
```

Then you may set the correct drivers:

```
sudo modprobe vfio_pci
echo 1002 6739 | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id
echo 1002 aa88 | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id
```

### PCI passthrough Helper Scripts

I created two scripts to help me correctly bind drivers for passthrough.
With these scripts, I do NOT set `/sys/bus/pci/drivers` and
`/sys/bus/pci/devices` manually as specified above.

The first is [device_bind.sh](./device_bind.sh), which will set the drivers for devices at a
given PCI address (eg: `sudo ./device_bind.sh 0000:01:00.0`)

The other, [enable_passthrough.sh](./enable_passthrough.sh), just calls `device_bind.sh` with all of the devices that I want to
configure for passthrough:

I also have a script [lsgroup.sh](./lsgroup.sh) that shows the addresses of all PCI
devices and their corresponding iommu groups. This script is used just for
info and troubleshooting.

### Networking Helper Scripts

[cubicool/qemu-net](https://github.com/cubicool/qemu-net) is a utility that
simplifies TUN/TAP interface creation/deletion and bridging.

If you want to redirect traffic on the host machine to a specific interface
(Linux kernel IP routing table manipulation):
```
sudo route add -net 10.10.2.0 netmask 255.255.255.0 dev tap01
sudo route add -net 10.10.2.0 netmask 255.255.255.0 gw 10.10.2.1
# continue to route traffic by default to your main host interface
sudo route add default gw 10.1.1.1 eth0

```

## Example QEMU commands

Note that I use `QEMU emulator version 2.0.0 (Debian 2.0.0+dfsg-2ubuntu1.30)`

### Windows 7 with PCI passthrough

```
sudo qemu-system-x86_64 \
  -enable-kvm -cpu host -smp cores=2,threads=1,sockets=1 -m 4096 \
  -monitor stdio \
  -usb \
  -soundhw ac97 \
  -device vfio-pci,host=01:00.0 \
  -device vfio-pci,host=01:00.1 \
  -device usb-ehci,id=ehci \
  -device usb-host,bus=ehci.0,vendorid=0x08a9,productid=0x0015 \
  -device usb-host,bus=ehci.0,vendorid=0x0424,productid=0x2512 \
  -hda /dev/mint-vg/windowsvg
```

Note the `usb-host` devices - I'm also telling QEMU to take control of
USB devices that would otherwise belong to the host. This can also be
done through the QEMU monitor (enabled via `-monitor stdio`):

```
#(qemu) device_add usb-host,bus=usb-bus.0,hostbus=3,hostport=9.2,id=myusbdevice
```

Remove with:
```
#(qemu) device_del myusbdevice
```

Find with:
```
#(qemu) info usb
#(qemu) info usbhost
```

Installing Windows 7 was done by attaching a CDROM ISO:

```
sudo qemu-system-x86_64 \
  -enable-kvm -cpu host -smp cores=2,threads=1,sockets=1 -m 4096 \
  -device vfio-pci,host=01:00.0 \
  -device vfio-pci,host=01:00.1 \
  -boot d -cdrom ../virtual_cds/win7x64u.iso \
  -hda /dev/mint-vg/windowsvg
```

The above command could be modified to attach any other CD at boot-time by merely
changing the iso given to the `-cdrom` option.

### Live VMs

Booting a VM from a live CD without persistence merely requires using the "boot"
device without any storage:

```
sudo qemu-system-x86_64 \
  -enable-kvm -cpu host -smp cores=2,threads=1,sockets=1 -m 5120 \
  -monitor stdio \
  -boot d -cdrom ../virtual_cds/kali-linux-1.1.0a-amd64.iso
```

## Resources

The Debian wiki was immensely helpful:

https://wiki.debian.org/VGAPassthrough

Additional information:

http://cromwell-intl.com/linux/openbsd-qemu-windows-howto.html#installqemu

https://bbs.archlinux.org/viewtopic.php?id=162768
