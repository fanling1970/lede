#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 修改 device 设备名称
sed -i "s/hostname='.*'/hostname='OpenWrt'/g" package/base-files/files/bin/config_generate

# 修改 固件版本 显示名称
# sed -i "s/ImmortalWrt/OpenWrt/g" Config.in
# sed -i "s/ImmortalWrt/OpenWrt/g" include/version.mk
# sed -i "s/ImmortalWrt/OpenWrt/g" config/Config-images.in
# sed -i "s/ImmortalWrt/OpenWrt/g" package/base-files/image-config.in

# 默认网关 ip 地址修改
sed -i 's/192.168.1.1/10.10.10.1/g' package/base-files/files/bin/config_generate

# 修改 wifi 无线名称
sed -i "s/ImmortalWrt/OpenWrt/g" package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc

# 修改 wifi 无线名称 & 密码
sed -i "s/BASE_SSID='.*'/BASE_SSID='OpenWrt'/g" target/linux/qualcommax/base-files/etc/uci-defaults/990_set-wireless.sh
sed -i "s/BASE_WORD='.*'/BASE_WORD='password'/g" target/linux/qualcommax/base-files/etc/uci-defaults/990_set-wireless.sh

# 最大连接数修改为65535
# sed -i "s/nf_conntrack_max=.*/nf_conntrack_max=65535/g" package/kernel/linux/files/sysctl-nf-conntrack.conf
# sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf

# 修改 luci 文件，添加 NSS Load 相关状态显示
# sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const fd = popen(access('/sbin/cpuinfo') ? '/sbin/cpuinfo' : \"top -n1 | awk \\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\'\")#g"

# 修改 wifi 默认打开
# sed -i "s/disabled='${defaults ? 0 : 1}'/disabled='0'/g" package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc

# 更换 Kernel 内核版本
# sed -i "s/KERNEL_PATCHVER:=6.6/KERNEL_PATCHVER:=6.12/g" target/linux/qualcommax/Makefile

# samba 解除 root 限制
# sed -i 's/invalid users = root/#&/g' feeds/packages/net/samba4/files/smb.conf.template

# 调整插件显示位置
# sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
# sed -i 's/services/nas/g' feeds/luci/applications/luci-app-openlist/root/usr/share/luci/menu.d/luci-app-openlist.json
# sed -i 's/services/nas/g' feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json
# sed -i 's/services/nas/g' feeds/luci/applications/luci-app-hd-idle/root/usr/share/luci/menu.d/luci-app-hd-idle.json
# sed -i 's/services/nas/g' feeds/luci/applications/luci-app-minidlna/root/usr/share/luci/menu.d/luci-app-minidlna.json
# sed -i 's/services/network/g' feeds/luci/applications/luci-app-eqos/root/usr/share/luci/menu.d/luci-app-eqos.json
# sed -i 's/services/network/g' feeds/luci/applications/luci-app-wol/root/usr/share/luci/menu.d/luci-app-wol.json
# sed -i 's/services/network/g' feeds/luci/applications/luci-app-wifischedule/root/usr/share/luci/menu.d/luci-app-wifischedule.json

# 取消 bootstrap 为默认主题，添加 argon 主题设置为默认
# rm -rf feeds/luci/themes/luci-theme-argon
# git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
# git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config

# sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' ./feeds/luci/collections/luci/Makefile

# 更新 golang 依赖（ mosdns & alist 插件 )
# rm -rf feeds/packages/lang/golang
# git clone --depth=1 -b 25.x https://github.com/sbwml/packages_lang_golang.git  feeds/packages/lang/golang

# 替换 geodata 依赖
# rm -rf feeds/packages/net/v2ray-geodata
# git clone --depth=1 https://github.com/sbwml/v2ray-geodata.git package/v2ray-geodata

# AdguardHome
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/luci/applications/luci-app-adguardhome
git clone --depth=1 -b dev https://github.com/stevenjoezhang/luci-app-adguardhome.git package/luci-app-adguardhome
# git clone --depth=1 -b main https://github.com/TanZhiwen2001/luci-app-adguardhome.git package/luci-app-adguardhome
# git clone --depth=1 -b lua https://github.com/sirpdboy/luci-app-adguardhome.git package/luci-app-adguardhome
# git clone --depth=1 https://github.com/kongfl888/luci-app-adguardhome.git package/luci-app-adguardhome
# git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome

# mosdns
rm -rf feeds/packages/net/mosdns
rm -rf feeds/luci/applications/luci-app-mosdns
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns

# smartdns
# rm -rf feeds/packages/net/smartdns
# rm -rf feeds/luci/applications/luci-app-smartdns
# git clone --depth=1 https://github.com/pymumu/openwrt-smartdns.git package/smartdns
# git clone --depth=1 https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns

# passwall(2) ( SingBox & Xray Kernel )
# 移除 openwrt feeds 过时的luci版本
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-passwall2
git clone --depth=1 -b main https://github.com/xiaorouji/openwrt-passwall.git package/luci-app-passwall
git clone --depth=1 -b main https://github.com/xiaorouji/openwrt-passwall2.git package/luci-app-passwall2

# 移除 openwrt feeds 自带的核心库
# rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box}
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone --depth=1 -b main https://github.com/xiaorouji/openwrt-passwall-packages.git package/passwall-packages

# OpenClash（ dev 版 ）( Mihomo Kernel )
rm -rf feeds/luci/applications/luci-app-openclash
git clone --depth=1 -b dev https://github.com/vernesong/OpenClash.git package/luci-app-openclash
# git clone -b master https://github.com/vernesong/OpenClash.git package/luci-app-openclash

# nikki( Mihomo Kernel )
git clone --depth=1 -b main https://github.com/nikkinikki-org/OpenWrt-nikki.git package/luci-app-nikki

# fchomo( Mihomo Kernel ) openwrt ≥ 24.10 
# git clone --depth=1 -b master https://github.com/fcshark-org/openwrt-fchomo.git package/openwrt-fchomo

# homeproxy( SingBox Kernel )
# rm -rf feeds/luci/applications/luci-app-homeproxy
# git clone --depth=1 -b dev https://github.com/immortalwrt/homeproxy.git package/luci-app-homeproxy

# momo ( SingBox Kernel ) openwrt ≥ 24.10 
# git clone --depth=1 -b main https://github.com/nikkinikki-org/OpenWrt-momo.git package/luci-app-momo

# nekobox ( SingBox Kernel )
# git clone --depth=1 -b main https://github.com/Thaolga/openwrt-nekobox.git package/openwrt-nekobox

# neko ( SingBox Kernel )
# git clone --depth=1 -b main https://github.com/nosignals/openwrt-neko.git package/openwrt-neko

# helloworld（ Xray Kernel ）
# git clone --depth=1 https://github.com/fw876/helloworld.git package/helloworld

# xray ( Xray Kernel )
# git clone --depth=1 https://github.com/yichya/luci-app-xray.git package/luci-app-xray
# git clone --depth=1 https://github.com/xiechangan123/luci-i18n-xray-zh-cn.git package/luci-i18n-xray-zh-cn

# 科学插件大全，移除 openwrt feeds 自带的核心包
# rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
# git clone --depth=1 https://github.com/sbwml/openwrt_helloworld.git package/helloworld

# daed
# rm -rf feeds/packages/net/daed
# rm -rf feeds/luci/applications/luci-app-daed
# git clone --depth=1 -b main https://github.com/QiuSimons/luci-app-daed.git package/luci-app-daed

# openlist
# rm -rf feeds/packages/net/openlist
# rm -rf feeds/luci/applications/luci-app-openlist
# git clone --depth=1 https://github.com/sbwml/luci-app-openlist2.git package/luci-app-openlist2

# 集客 AC
git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac.git package/openwrt-gecoosac

# lucky
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky

# webdav ( openwrt ≥ 24.10 ) 
# git clone --depth=1 -b openwrt-24.10 https://github.com/sbwml/luci-app-webdav.git package/luci-app-webdav

# luci-app-diskman
# rm -rf feeds/luci/applications/luci-app-diskman
# git clone --depth=1 https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# filemanager
# git clone --depth=1 -b main https://github.com/sbwml/luci-app-filemanager.git package/luci-app-filemanager

# jdCloud ax6600 led screen ctrl
# git clone --depth=1 -b main https://github.com/NONGFAH/luci-app-athena-led.git package/luci-app-athena-led

# 修复 jdCloud ax6600 无限重启
rm -rf package/kernel/mac80211/patches/nss/ath11k/999-900-bss-transition-handling.patch

# 修复 rust 报错
wget -O feeds/packages/lang/rust/Makefile https://raw.githubusercontent.com/aimetu/OpenWrt-Actions/refs/heads/main/patches/Makefile
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile

./scripts/feeds update -a
./scripts/feeds install -a
