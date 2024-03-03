#!/bin/bash
alias wget="$(which wget) --https-only --retry-connrefused"
set -e
set -x
# get the latest release version of 23.05
LATESTRELEASE=$(curl -sSf -H 'X-GitHub-Api-Version: 2022-11-28' https://api.github.com/repos/openwrt/openwrt/tags | jq '.[].name' -r | grep -v 'rc' | grep 'v23' | sort -r | head -n 1)

echo "LATESTRELEASE=$LATESTRELEASE" >> ./OPENWRT_GIT_TAG

git clone --single-branch -b 'openwrt-23.05'  --depth 1  https://github.com/openwrt/openwrt.git openwrt_snapshot
git clone --single-branch -b "$LATESTRELEASE" --depth 1  https://github.com/openwrt/openwrt.git openwrt

rm -rf ./openwrt/package/
mv -f  ./openwrt_snapshot/package            ./openwrt/package
mv -f  ./openwrt_snapshot/feeds.conf.default ./openwrt/feeds.conf.default
rm -rf ./openwrt_snapshot/
pushd openwrt
  rm -rf ./package/base-files/ ./package/firmware/ ./package/kernel/ ./package/Makefile
  git checkout HEAD package/base-files/
  git checkout HEAD package/firmware/
  git checkout HEAD package/kernel/
  git checkout HEAD package/Makefile
popd

# 获取额外代码
git clone -b openwrt-23.05 --depth 1 https://github.com/immortalwrt/immortalwrt.git    Immortalwrt_2305/
sleep 3
git clone -b master        --depth 1 https://github.com/immortalwrt/packages.git       Immortalwrt_PKG/
sleep 3
git clone -b openwrt-23.05 --depth 1 https://github.com/immortalwrt/luci.git           Immortalwrt_Luci_2305/
sleep 3
git clone -b master        --depth 1 https://github.com/coolsnowwolf/lede.git          Coolsnowwolf_MSTR/
sleep 3
git clone -b master        --depth 1 https://github.com/coolsnowwolf/packages.git      Coolsnowwolf_PKG/
sleep 3
git clone -b 23.05         --depth 1 https://github.com/Lienol/openwrt.git             Lienol_MSTR/
sleep 3
git clone -b main          --depth 1 https://github.com/Lienol/openwrt-package.git     Lienol_PKG/
sleep 3
git clone -b master        --depth 1 https://github.com/QiuSimons/OpenWrt-Add.git      OpenWrt-Add/
sleep 3
git clone -b master        --depth 1 https://github.com/openwrt/packages.git           Openwrt_PKG_MSTR/
sleep 3
git clone -b main          --depth 1 https://github.com/jjm2473/openwrt-third.git      Jjm2473_PACKAGES/
sleep 3
git clone -b main          --depth 1 https://github.com/fw876/helloworld.git           SSRP_SRC/
sleep 3
git clone -b v5            --depth 1 https://github.com/sbwml/openwrt_helloworld.git   Sbwml_SSRP_SRC/
sleep 3
git clone -b main          --depth 1 https://github.com/xiaorouji/openwrt-passwall-packages.git Passwall_PKG/
sleep 3
git clone -b main          --depth 1 https://github.com/sbwml/luci-app-daed-next.git     Sbw_daednext/
sleep 3
git clone -b rebase        --depth 1 https://github.com/QiuSimons/luci-app-daed-next.git Luci_daednext/

unalias wget
exit 0
