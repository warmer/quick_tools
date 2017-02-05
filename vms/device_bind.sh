#!/bin/bash

modprobe vfio-pci
for dev in "$@"; do
  vendor=$(cat /sys/bus/pci/devices/$dev/vendor | grep -oP '[a-f0-9]*$')
  device=$(cat /sys/bus/pci/devices/$dev/device | grep -oP '[a-f0-9]*$')
  echo "vendor $vendor"
  echo "device $device"
  if [ -e /sys/bus/pci/devices/$dev/driver ]; then
    echo "$dev > /sys/bus/pci/devices/$dev/driver/unbind"
    echo $dev > /sys/bus/pci/devices/$dev/driver/unbind
  fi
  echo "$vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id"
  echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id
done
