#!/usr/bin/env bash
set -euo pipefail

mkdir -p /srv/tftpboot
cp -f /usr/lib/ipxe/undionly.kpxe /srv/tftpboot/undionly.kpxe
cp -f /usr/lib/ipxe/snponly.efi /srv/tftpboot/ipxe.efi

exec in.tftpd --foreground --secure /srv/tftpboot
