#!/bin/bash
# 如果没有环境变量或无效，则默认构建R2S版本
[ -f "../SEED/${MYOPENWRTTARGET}.config.seed" ] || MYOPENWRTTARGET='R2S'
echo "==> Now building: ${MYOPENWRTTARGET}"

alias wget="$(which wget) --https-only --retry-connrefused"
set -e
set -x
### 1. 基本 ###
# 获取软件源
./scripts/feeds update -a
./scripts/feeds install -a
# 配置启用 nf_conntrack_helper
echo "net.netfilter.nf_conntrack_helper=1" >> package/kernel/linux/files/sysctl-nf-conntrack.conf
# 创建可能需要的目录
mkdir -p package/new

### 2. 补丁 ###
# BBR v3
mv -f ../PATCH/BBRv3/kernel/* ./target/linux/generic/backport-5.15/
# LRNG
mv -f ../PATCH/LRNG/*         ./target/linux/generic/hack-5.15/
echo '
# CONFIG_RANDOM_DEFAULT_IMPL is not set
CONFIG_LRNG=y
# CONFIG_LRNG_IRQ is not set
CONFIG_LRNG_JENT=y
CONFIG_LRNG_CPU=y
# CONFIG_LRNG_SCHED is not set
' >> ./target/linux/generic/config-5.15
# mbedTLS
rm -rf ./package/libs/mbedtls
mv ../Immortalwrt_2305/package/libs/mbedtls/ ./package/libs/mbedtls/
# fstool patch
wget -qO - https://github.com/coolsnowwolf/lede/commit/8a4db762497b79cac91df5e777089448a2a71f7c.patch | patch -p1
# R8152 网卡驱动
mv -f ../Immortalwrt_2305/package/kernel/r8152/ ./package/new/r8152/
# R8125 网卡驱动
git clone --depth 1 https://github.com/sbwml/package_kernel_r8125 package/new/r8125
# R8168 网卡驱动 (务必放到 package/new/r8168 目录，否则后续 Patch 会出错)
git clone --depth 1 https://github.com/BROBIRD/openwrt-r8168.git  package/new/r8168
# 默认开启 irqbalance
sed -i "s/option enabled '0'/option enabled '1'/g" ./feeds/packages/utils/irqbalance/files/irqbalance.config
# UPX
sed -i '/patchelf pkgconf/i\tools-y += ucl upx'                                  ./tools/Makefile
sed -i '\/autoconf\/compile :=/i\$(curdir)/upx/compile := $(curdir)/ucl/compile' ./tools/Makefile
mv -f ../Lienol_MSTR/tools/ucl/ ./tools/ucl/
mv -f ../Lienol_MSTR/tools/upx/ ./tools/upx/
# Node.js 使用预编译二进制
rm -rf ./feeds/packages/lang/node
git clone --depth 1 https://github.com/sbwml/feeds_packages_lang_node-prebuilt.git feeds/packages/lang/node
# nftables 额外规则
mkdir -p                               files/usr/share/nftables.d/chain-pre/forward
mv ../PATCH/nftables_conf/10-ios.nft ./files/usr/share/nftables.d/chain-pre/forward/
# hotplug 配置
mkdir -p                                                 files/etc/hotplug.d/net
mv ../PATCH/hotplug_conf/01-maximize_nic_rx_tx_buffers ./files/etc/hotplug.d/net/
# 根据体系调整
case ${MYOPENWRTTARGET} in
  R2S)
    # 平台优化
    sed -i 's/-Os/-O2/g' ./include/target.mk
    sed -i 's,-mcpu=generic,-march=armv8-a,g' ./include/target.mk
    # 显示 ARM64 CPU 型号
    mv -f ../Immortalwrt_2305/target/linux/generic/hack-5.15/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch ./target/linux/generic/hack-5.15/
    # Patch R8168 网卡驱动
    patch -p1 < ../PATCH/r8168/r8168-fix_LAN_led-for_r4s-from_TL.patch
    # 更换为 ImmortalWrt Uboot 以及 Target
    rm -rf ./package/boot/arm-trusted-firmware-rockchip ./package/boot/uboot-rockchip ./target/linux/rockchip
    cp -r ../Immortalwrt_2305/package/boot/arm-trusted-firmware-rockchip/ ./package/boot/arm-trusted-firmware-rockchip/
    cp -r ../Immortalwrt_2305/package/boot/uboot-rockchip/                ./package/boot/uboot-rockchip/
    mv -f ../Immortalwrt_2305/target/linux/rockchip/                      ./target/linux/rockchip/
    mv -f ../PATCH/rockchip-5.15/*                                        ./target/linux/rockchip/patches-5.15/
    ;;
  x86)
    # 平台优化，不再考虑过于老旧的平台
    sed -i 's/-Os/-O2 -march=x86-64-v2/g' ./include/target.mk
    # x86 csum
    mv -f ../PATCH/backport/x86_csum/* ./target/linux/generic/backport-5.15/
    # Enable SMP
echo '
CONFIG_X86_INTEL_PSTATE=y
CONFIG_SMP=y
' >> ./target/linux/x86/config-5.15
    # 系统型号字符串
    echo '# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

if grep -q "Default string" /tmp/sysinfo/model 2>/dev/null; then
    echo "Compatible PC" > /tmp/sysinfo/model
fi

exit 0
' > ./package/base-files/files/etc/rc.local
    # Intel I915
    wget -qO - https://github.com/openwrt/openwrt/commit/9c58addc0bbeb27049ec3f994bcb0846a6a35b1c.patch | patch -p1
    wget -qO - https://github.com/openwrt/openwrt/commit/64f1a65736a0c265b764071bf3ee6224438ac400.patch | patch -p1
    wget -qO - https://github.com/openwrt/openwrt/commit/c21a357093afc1ffeec11b6bb63d241899c1cf68.patch | patch -p1
    sed -i '/I915/d' ./target/linux/x86/64/config-5.15
    # igc fix
    mv -f ../Coolsnowwolf_MSTR/target/linux/x86/patches-5.15/996-intel-igc-i225-i226-disable-eee.patch ./target/linux/x86/patches-5.15/
    ;;
esac

### 3. Fullcone-NAT 部分 ###
# Patch Kernel 以解决 FullCone 冲突
mv -f ../Coolsnowwolf_MSTR/target/linux/generic/hack-5.15/952-add-net-conntrack-events-support-multiple-registrant.patch ./target/linux/generic/hack-5.15/
mv -f ../Coolsnowwolf_MSTR/target/linux/generic/hack-5.15/982-add-bcm-fullconenat-support.patch                          ./target/linux/generic/hack-5.15/
# Patch FireWall 以增添 FullCone 功能
# FW4
mkdir -p package/network/config/firewall4/patches package/network/utils/nftables/patches package/libs/libnftnl/patches
mv -f ../PATCH/firewall/001-fix-fw4-flow-offload.patch                              ./package/network/config/firewall4/patches/
mv -f ../PATCH/firewall/990-unconditionally-allow-ct-status-dnat.patch              ./package/network/config/firewall4/patches/
mv -f ../PATCH/firewall/999-01-firewall4-add-fullcone-support.patch                 ./package/network/config/firewall4/patches/
mv -f ../PATCH/firewall/nftables/002-nftables-add-fullcone-expression-support.patch ./package/network/utils/nftables/patches/
mv -f ../PATCH/firewall/libnftnl/001-libnftnl-add-fullcone-expression-support.patch ./package/libs/libnftnl/patches/
sed -i '/PKG_INSTALL:=/iPKG_FIXUP:=autoreconf'                                      ./package/libs/libnftnl/Makefile
# FW3
mkdir -p package/network/config/firewall/patches
wget -P ./package/network/config/firewall/patches/ https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-21.02/package/network/config/firewall/patches/100-fullconenat.patch
mv -f ../Coolsnowwolf_MSTR/package/network/config/firewall/patches/101-bcm-fullconenat.patch ./package/network/config/firewall/patches/
# iptables
mv -f ../Coolsnowwolf_MSTR/package/network/utils/iptables/patches/900-bcm-fullconenat.patch ./package/network/utils/iptables/patches/900-bcm-fullconenat.patch
# network
wget -qO - https://github.com/openwrt/openwrt/commit/bbf39d07fd43977f55a4b9ba9e384cdf8a0d2b50.patch | patch -p1
# Patch LuCI 以增添 FullCone 开关
pushd feeds/luci
  patch -p1 < ../../../PATCH/firewall/luci-app-firewall_add_fullcone_fw4.patch
popd
# FullCone package
git clone --depth 1 https://github.com/fullcone-nat-nftables/nft-fullcone.git package/new/nft-fullcone
mv -f ../Lienol_MSTR/package/network/utils/fullconenat/                     ./package/new/fullconenat/

### 4. 软件包 ###
# dae
mv -f ../Immortalwrt_PKG/net/dae          ./feeds/packages/net/dae
mv -f ../Immortalwrt_PKG/net/daed         ./feeds/packages/net/daed
ln -sf ../../../feeds/packages/net/dae    ./package/feeds/packages/dae
ln -sf ../../../feeds/packages/net/daed   ./package/feeds/packages/daed
mv -f ../Luci_daednext/daed-next          ./package/new/daed-next
mv -f ../Luci_daednext/luci-app-daed-next ./package/new/luci-app-daed-next
git clone --single-branch -b master --depth 1 https://github.com/QiuSimons/luci-app-daed.git package/new/luci-app-daed
# allow BTF mismatch
wget -qO - https://github.com/immortalwrt/immortalwrt/commit/73e56799fe86dce851c6cf07a768e81597e204d9.patch | patch -p1
wget -P ./target/linux/generic/backport-5.15/ https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-23.05/target/linux/generic/backport-5.15/051-v5.18-bpf-Add-config-to-allow-loading-modules-with-BTF-mismatch.patch
# cgroup v2
pushd feeds/packages
  patch -p1 < ../../../PATCH/cgroupfs-mount/0001-fix-cgroupfs-mount.patch
popd
mkdir -p feeds/packages/utils/cgroupfs-mount/patches
mv -f ../PATCH/cgroupfs-mount/900-mount-cgroup-v2-hierarchy-to-sys-fs-cgroup-cgroup2.patch   ./feeds/packages/utils/cgroupfs-mount/patches/
mv -f ../PATCH/cgroupfs-mount/901-fix-cgroupfs-umount.patch                                  ./feeds/packages/utils/cgroupfs-mount/patches/
mv -f ../PATCH/cgroupfs-mount/902-mount-sys-fs-cgroup-systemd-for-docker-systemd-suppo.patch ./feeds/packages/utils/cgroupfs-mount/patches/
# AutoCore
mv -f ../Immortalwrt_2305/package/emortal/autocore/                        ./package/new/autocore/
sed -i 's/ "getTempInfo" / "getTempInfo", "getCPUBench", "getCPUUsage" /g' ./package/new/autocore/files/luci-mod-status-autocore.json
mv -f ../OpenWrt-Add/autocore/files/x86/autocore ./package/new/autocore/files/autocore
sed -i '/i386 i686 x86_64/{n;n;n;d;}'             ./package/new/autocore/Makefile
sed -i '/i386 i686 x86_64/d'                      ./package/new/autocore/Makefile
rm -rf ./feeds/luci/modules/luci-base
mv -f ../Immortalwrt_Luci_2305/modules/luci-base/ ./feeds/luci/modules/luci-base/
sed -i 's,(br-lan),,g'                            ./feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci
rm -rf ./feeds/luci/modules/luci-mod-status
mv -f ../Immortalwrt_Luci_2305/modules/luci-mod-status/ ./feeds/luci/modules/luci-mod-status/
# coremark
rm -rf ./feeds/packages/utils/coremark
mv -f ../Immortalwrt_PKG/utils/coremark/     ./feeds/packages/utils/coremark/
mv -f ../Immortalwrt_2305/package/utils/mhz/ ./package/utils/mhz/
# UPnP
rm -rf ./feeds/packages/net/miniupnpd
mv -f ../Openwrt_PKG_MSTR/net/miniupnpd/ ./feeds/packages/net/miniupnpd/
# luci-app-irqbalance
mv -f ../OpenWrt-Add/luci-app-irqbalance/ ./package/new/luci-app-irqbalance/
# CPU 控制相关
mv -f ../Immortalwrt_PKG/utils/cpulimit/          ./feeds/packages/utils/cpulimit/
mv -f ../Immortalwrt_Luci_2305/applications/luci-app-cpulimit/ ./package/new/luci-app-cpulimit/
mv -f ../Immortalwrt_Luci_2305/applications/luci-app-cpufreq/  ./feeds/luci/applications/luci-app-cpufreq/
ln -sf ../../../feeds/packages/utils/cpulimit            ./package/feeds/packages/cpulimit
ln -sf ../../../feeds/luci/applications/luci-app-cpufreq ./package/feeds/luci/luci-app-cpufreq
# DDNS
sed -i '/boot()/,+2d' feeds/packages/net/ddns-scripts/files/etc/init.d/ddns
mv -f ../Jjm2473_PACKAGES/ddns-scripts_aliyun/ ./feeds/packages/net/ddns-scripts_aliyun/
ln -sf ../../../feeds/packages/net/ddns-scripts_aliyun ./package/feeds/packages/ddns-scripts_aliyun
# IPv6 兼容助手
mv -f ../Coolsnowwolf_MSTR/package/lean/ipv6-helper/ ./package/new/ipv6-helper/
patch -p1 < ../PATCH/odhcp6c/1002-odhcp6c-support-dhcpv6-hotplug.patch
# odhcpd IPv6
mkdir -p package/network/services/odhcpd/patches
mv -f ../PATCH/odhcpd/0001-odhcpd-improve-RFC-9096-compliance.patch ./package/network/services/odhcpd/patches/
mkdir -p                              files/etc/hotplug.d/iface
mv -f ../PATCH/odhcpd/99-zzz-odhcpd ./files/etc/hotplug.d/iface/
# OpenClash
git clone --single-branch -b master --depth 1 https://github.com/vernesong/OpenClash.git package/new/luci-app-openclash
# SSRP
mv -f ../SSRP_SRC/luci-app-ssr-plus/ ./package/new/luci-app-ssr-plus/
pushd package/new
  if grep -qF 'firewall.shadowsocksr_server' luci-app-ssr-plus/root/etc/init.d/shadowsocksr 2>/dev/null; then
    wget -qO - https://github.com/fw876/helloworld/pull/1249.patch | patch -p1
  fi
  patch -p1 < ../../../PATCH/SSRP/0001-add-QiuSimons-Chnroute-to-chnroute-url.patch
popd
# SSRP 依赖
rm -rf ./feeds/packages/net/kcptun
rm -rf ./feeds/packages/net/microsocks
rm -rf ./feeds/packages/net/shadowsocks-libev
rm -rf ./feeds/packages/net/trojan-go
rm -rf ./feeds/packages/net/v2ray-core
rm -rf ./feeds/packages/net/v2ray-geodata
rm -rf ./feeds/packages/net/xray-core
mv -f ../Coolsnowwolf_PKG/net/shadowsocks-libev/      ./feeds/packages/net/shadowsocks-libev/
mv -f ../Immortalwrt_PKG/net/kcptun/                  ./feeds/packages/net/kcptun/
mv -f ../Immortalwrt_PKG/net/xray-core/               ./feeds/packages/net/xray-core/
mv -f ../Passwall_PKG/brook/                          ./package/new/brook/
mv -f ../Passwall_PKG/chinadns-ng/                    ./package/new/chinadns-ng/
mv -f ../Passwall_PKG/dns2socks/                      ./package/new/dns2socks/
mv -f ../Passwall_PKG/hysteria/                       ./package/new/hysteria/
mv -f ../Passwall_PKG/ipt2socks/                      ./package/new/ipt2socks/
mv -f ../Passwall_PKG/microsocks/                     ./feeds/packages/net/microsocks/
mv -f ../Passwall_PKG/pdnsd-alt/                      ./package/new/pdnsd/
mv -f ../Passwall_PKG/ssocks/                         ./package/new/ssocks/
mv -f ../Passwall_PKG/tcping/                         ./package/new/tcping/
mv -f ../Passwall_PKG/trojan-go/                      ./feeds/packages/net/trojan-go/
mv -f ../Passwall_PKG/trojan-plus/                    ./package/new/trojan-plus/
mv -f ../Passwall_PKG/xray-plugin/                    ./package/new/xray-plugin/
mv -f ../SSRP_SRC/dns2tcp/                            ./package/new/dns2tcp/
mv -f ../SSRP_SRC/gn/                                 ./package/new/gn/
mv -f ../SSRP_SRC/lua-neturl/                         ./package/new/lua-neturl/
mv -f ../SSRP_SRC/mosdns/                             ./package/new/mosdns/
mv -f ../SSRP_SRC/naiveproxy/                         ./package/new/naiveproxy/
mv -f ../SSRP_SRC/redsocks2/                          ./package/new/redsocks2/
mv -f ../SSRP_SRC/shadow-tls/                         ./package/new/shadow-tls/
mv -f ../SSRP_SRC/shadowsocks-rust/                   ./package/new/shadowsocks-rust/
mv -f ../SSRP_SRC/shadowsocksr-libev/                 ./package/new/shadowsocksr-libev/
mv -f ../SSRP_SRC/simple-obfs/                        ./package/new/simple-obfs/
mv -f ../SSRP_SRC/trojan/                             ./package/new/trojan/
mv -f ../SSRP_SRC/tuic-client/                        ./package/new/tuic-client/
mv -f ../SSRP_SRC/v2ray-core/                         ./feeds/packages/net/v2ray-core/
mv -f ../SSRP_SRC/v2ray-geodata/                      ./feeds/packages/net/v2ray-geodata/
mv -f ../SSRP_SRC/v2ray-plugin/                       ./package/new/v2ray-plugin/
sed -i '/CURDIR/d' ./feeds/packages/net/xray-core/Makefile
ln -sf ../../../feeds/packages/net/kcptun             ./package/feeds/packages/kcptun
ln -sf ../../../feeds/packages/net/microsocks         ./package/feeds/packages/microsocks
ln -sf ../../../feeds/packages/net/shadowsocks-libev  ./package/feeds/packages/shadowsocks-libev
ln -sf ../../../feeds/packages/net/trojan-go          ./package/feeds/packages/trojan-go
ln -sf ../../../feeds/packages/net/v2ray-core         ./package/feeds/packages/v2ray-core
ln -sf ../../../feeds/packages/net/v2ray-geodata      ./package/feeds/packages/v2ray-geodata
ln -sf ../../../feeds/packages/net/xray-core          ./package/feeds/packages/xray-core
# homeproxy
git clone --single-branch -b master --depth 1 https://github.com/immortalwrt/homeproxy.git package/new/homeproxy
rm -rf ./feeds/packages/net/sing-box
mv -f ../Immortalwrt_PKG/net/sing-box/ ./feeds/packages/net/sing-box/
ln -sf ../../../feeds/packages/net/sing-box ./package/feeds/packages/sing-box
# v2raya
rm -rf ./feeds/packages/net/v2raya
mv -f ../Openwrt_PKG_MSTR/net/v2raya/ ./feeds/packages/net/v2raya/
ln -sf ../../../feeds/packages/net/v2raya ./package/feeds/packages/v2raya
# Passwall
git clone --single-branch -b main --depth 1 https://github.com/xiaorouji/openwrt-passwall.git _tmp_luci-app-passwall
mv -f ./_tmp_luci-app-passwall/luci-app-passwall/ ./package/new/luci-app-passwall/
rm -rf ./_tmp_luci-app-passwall
echo '
teamviewer.com
epicgames.com
dangdang.com
account.synology.com
ddns.synology.com
checkip.synology.com
checkip.dyndns.org
checkipv6.synology.com
ntp.aliyun.com
cn.ntp.org.cn
ntp.ntsc.ac.cn
' >> ./package/new/luci-app-passwall/root/usr/share/passwall/rules/direct_host
# 订阅转换
mv -f ../Immortalwrt_PKG/net/subconverter/ ./feeds/packages/net/subconverter/
mv -f ../Immortalwrt_PKG/libs/jpcre2/      ./feeds/packages/libs/jpcre2/
mv -f ../Immortalwrt_PKG/libs/rapidjson/   ./feeds/packages/libs/rapidjson/
mv -f ../Immortalwrt_PKG/libs/libcron/     ./feeds/packages/libs/libcron/
mv -f ../Immortalwrt_PKG/libs/quickjspp/   ./feeds/packages/libs/quickjspp/
mv -f ../Immortalwrt_PKG/libs/toml11/      ./feeds/packages/libs/toml11/
ln -sf ../../../feeds/packages/net/subconverter ./package/feeds/packages/subconverter
ln -sf ../../../feeds/packages/libs/jpcre2      ./package/feeds/packages/jpcre2
ln -sf ../../../feeds/packages/libs/rapidjson   ./package/feeds/packages/rapidjson
ln -sf ../../../feeds/packages/libs/libcron     ./package/feeds/packages/libcron
ln -sf ../../../feeds/packages/libs/quickjspp   ./package/feeds/packages/quickjspp
ln -sf ../../../feeds/packages/libs/toml11      ./package/feeds/packages/toml11
# 清理内存
mv -f ../Immortalwrt_Luci_2305/applications/luci-app-ramfree/ ./package/new/luci-app-ramfree/
# socat
mv -f ../Lienol_PKG/luci-app-socat/ ./package/new/luci-app-socat/
pushd package/new
  wget -qO - https://github.com/Lienol/openwrt-package/pull/39.patch | patch -p1
popd
sed -i '/socat\.config/d' feeds/packages/net/socat/Makefile
# 流量监测
git clone -b master --depth 1 https://github.com/brvphoenix/wrtbwmon.git          package/new/wrtbwmon
git clone -b master --depth 1 https://github.com/brvphoenix/luci-app-wrtbwmon.git package/new/luci-app-wrtbwmon
# Zerotier
rm -rf ./feeds/packages/net/zerotier
mv -f ../Immortalwrt_PKG/net/zerotier/                         ./feeds/packages/net/zerotier/
mv -f ../Immortalwrt_Luci_2305/applications/luci-app-zerotier/ ./feeds/luci/applications/luci-app-zerotier/
ln -sf ../../../feeds/luci/applications/luci-app-zerotier ./package/feeds/luci/luci-app-zerotier
# Argon 主题
git clone --single-branch -b master --depth 1 https://github.com/jerrykuku/luci-theme-argon.git      package/new/luci-theme-argon
git clone --single-branch -b master --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git package/new/luci-app-argon-config
# Edge 主题
git clone --single-branch -b master --depth 1 https://github.com/kiddin9/luci-theme-edge.git         package/new/luci-theme-edge
# 翻译及部分功能优化
mv -f ../OpenWrt-Add/addition-trans-zh/                               ./package/new/addition-trans-zh/
sed -i 's,iptables-mod-fullconenat,iptables-nft +kmod-nft-fullcone,g' ./package/new/addition-trans-zh/Makefile
if [ "${MYOPENWRTTARGET}" != 'R2S' ] ; then
  sed -i '/openssl\.cnf/d' ../PATCH/default_conf/zzz-default-settings
  sed -i '/upnp/Id'        ../PATCH/default_conf/zzz-default-settings
fi
mv -f ../PATCH/default_conf/zzz-default-settings ./package/new/addition-trans-zh/files/zzz-default-settings
# 给root用户添加vim和screen的配置文件
mkdir -p                   ./package/base-files/files/root/
mv -f ../PRECONFS/vimrc    ./package/base-files/files/root/.vimrc
mv -f ../PRECONFS/screenrc ./package/base-files/files/root/.screenrc

### 5. 编译参数调整 ###
# grub2
sed -i 's,no-lto,no-lto no-gc-sections,g'                       package/boot/grub2/Makefile
# openssl
sed -i 's,no-mips16 gc-sections,no-mips16 gc-sections no-lto,g' package/libs/openssl/Makefile
# libsodium
sed -i 's,no-mips16,no-mips16 no-lto,g'                         feeds/packages/libs/libsodium/Makefile
# nginx
sed -i 's,gc-sections,gc-sections no-lto,g'                     feeds/packages/net/nginx/Makefile

# 删除已有配置
rm -rf .config
# 停用内核配置“将所有警告视为错误”，这是因为一些第三方PATCH不够严谨
sed -i 's,CONFIG_WERROR=y,# CONFIG_WERROR is not set,g' ./target/linux/generic/config-5.15

### 6. vermagic ###
source ../OPENWRT_GIT_TAG
LATESTRELEASE=${LATESTRELEASE:1}
case ${MYOPENWRTTARGET} in
  R2S)
    wget "https://downloads.openwrt.org/releases/${LATESTRELEASE}/targets/rockchip/armv8/packages/Packages.gz"
    ;;
  x86)
    wget "https://downloads.openwrt.org/releases/${LATESTRELEASE}/targets/x86/64/packages/Packages.gz"
    ;;
esac
zgrep -m 1 "Depends: kernel (=.*)$" Packages.gz | sed -e 's/.*-\(.*\))/\1/' > .vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' ./include/kernel-defaults.mk
rm -f Packages.gz

# 删除多余的代码库
rm -rf ../Immortalwrt_2305 ../Immortalwrt_PKG ../Immortalwrt_Luci_2305 ../Coolsnowwolf_MSTR ../Coolsnowwolf_PKG ../Lienol_MSTR ../Lienol_PKG ../OpenWrt-Add ../Openwrt_PKG_MSTR ../Jjm2473_PACKAGES ../Passwall_PKG ../SSRP_SRC

unalias wget
sync