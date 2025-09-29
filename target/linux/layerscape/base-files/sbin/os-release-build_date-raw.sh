#!/bin/sh

BUILD_DATE=$(grep OPENWRT_BUILD_DATE /etc/os-release | cut -d '"' -f2)
echo "$BUILD_DATE"
