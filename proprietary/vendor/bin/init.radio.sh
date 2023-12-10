#! /vendor/bin/sh
#
# Copy /vendor/etc/database/ if needed for RIL
#
data_ecc_ver=$(cat /data/vendor/radio/database/ecc_version)
if [ -z $data_ecc_ver ]; then
    data_ecc_ver=0
fi
vendor_ecc_ver=$(cat /vendor/etc/database/ecc_version)
if [ -z $vendor_ecc_ver ]; then
    vendor_ecc_ver=0
fi
# Copy files from /vendor/etc/database/ to /data/vendor/radio/ when data_ecc_ver < vendor_ecc_ver
if [ $data_ecc_ver -lt $vendor_ecc_ver ]; then
    mkdir -p /data/vendor/radio/database
    cp -R /vendor/etc/database/* /data/vendor/radio/database/
    chown -hR radio.radio /data/vendor/radio/databse/
fi
