#!/vendor/bin/sh

max77759tcpc_path=/sys/devices/platform/10d60000.hsi2c/i2c-13/13-0025
if [ -d $max77759tcpc_path ]; then
  echo 0 > $max77759tcpc_path/contaminant_detection;
fi
