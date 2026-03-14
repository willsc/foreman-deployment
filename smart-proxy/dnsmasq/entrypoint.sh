#!/usr/bin/env bash
set -euo pipefail

template="/templates/managed.conf"
if [[ "${PROXY_DHCP_MODE:-managed}" != "managed" ]]; then
  template="/templates/external.conf"
fi

mkdir -p /etc/dnsmasq.d
sed \
  -e "s|__PXE_INTERFACE__|${PXE_INTERFACE}|g" \
  -e "s|__PXE_SUBNET__|${PXE_SUBNET}|g" \
  -e "s|__PXE_NETMASK__|${PXE_NETMASK}|g" \
  -e "s|__PXE_GATEWAY__|${PXE_GATEWAY}|g" \
  -e "s|__PXE_DNS_SERVERS__|${PXE_DNS_SERVERS}|g" \
  -e "s|__PXE_DHCP_RANGE_START__|${PXE_DHCP_RANGE_START}|g" \
  -e "s|__PXE_DHCP_RANGE_END__|${PXE_DHCP_RANGE_END}|g" \
  -e "s|__PXE_NEXT_SERVER__|${PXE_NEXT_SERVER}|g" \
  -e "s|__PXE_BOOTFILE_BIOS__|${PXE_BOOTFILE_BIOS}|g" \
  -e "s|__PXE_BOOTFILE_UEFI__|${PXE_BOOTFILE_UEFI}|g" \
  -e "s|__PXE_DOMAIN__|${PXE_DOMAIN}|g" \
  -e "s|__PROXY_HTTP_URL__|${PROXY_HTTP_URL}|g" \
  "${template}" > /etc/dnsmasq.d/pxe.conf

exec dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq.d/pxe.conf
