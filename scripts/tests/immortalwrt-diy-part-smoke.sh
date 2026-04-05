#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="$repo_root/build/Immortalwrt/diy-part.sh"

run_case() {
  local source_path="$1"
  local expect_file="$2"
  local expect_present="$3"

  local tmpdir
  tmpdir="$(mktemp -d)"

  (
    trap 'rm -rf "$tmpdir"' EXIT
    mkdir -p "$tmpdir/openwrt"
    cp "$source_path" "$tmpdir/diy-part.sh"

    cd "$tmpdir"
    CLEAR_PATH="$tmpdir/clear" DELETE="$tmpdir/delete" OPENWRT_ROOT="$tmpdir/openwrt" bash ./diy-part.sh >/dev/null 2>&1

    if [[ "$expect_present" == "yes" ]]; then
      local defaults_file="$tmpdir/openwrt/files/etc/uci-defaults/$expect_file"
      [[ -f "$defaults_file" ]]
      grep -q "network.lan.ipaddr='192.168.10.1'" "$defaults_file"
    else
      [[ ! -e "$tmpdir/openwrt/files/etc/uci-defaults/$expect_file" ]]
    fi
  )

}

tmp_nonzero_source="$(mktemp)"
tmp_zero_source="$(mktemp)"
trap 'rm -f "$tmp_nonzero_source" "$tmp_zero_source"' EXIT

cp "$source_file" "$tmp_nonzero_source"
cp "$source_file" "$tmp_zero_source"
sed -i 's/export Ipv4_ipaddr="192\.168\.10\.1"/export Ipv4_ipaddr="0"/' "$tmp_zero_source"

run_case "$tmp_nonzero_source" "99-immortalwrt-ipv4-ipaddr" yes

run_case "$tmp_zero_source" "99-immortalwrt-ipv4-ipaddr" no

printf 'immortalwrt diy-part smoke test passed\n'
