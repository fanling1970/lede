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
sed -i "s/hostname='.*'/hostname='LEDE'/g" package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='LEDE'/g" package/base-files/luci2/bin/config_generate

# 加入作者信息
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g" package/lean/default-settings/files/zzz-default-settings   
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By J.Y'/g" package/lean/default-settings/files/zzz-default-settings

sed -i "2iuci set istore.istore.channel='OpenWrt'" package/lean/default-settings/files/zzz-default-settings
sed -i "3iuci commit istore" package/lean/default-settings/files/zzz-default-settings

# 默认网关 ip 地址修改
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/luci2/bin/config_generate

# 修改 wifi 无线名称
sed -i "s/LEDE/JDC_AX6600/g" package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 清除默认密码 password
sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings

# 最大连接数修改为 65535
# sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf

# 更换 Kernel 内核
# sed -i "s/KERNEL_PATCHVER:=6.1/KERNEL_PATCHVER:=6.6/g" target/linux/qualcommax/Makefile

# 更换 bin 固件内核大小
# sed -i "s/factory.bin recovery.bin/factory.bin sysupgrade.bin/g" target/linux/qualcommax/image/ipq60xx.mk
# sed -i "s/pad-to 12288k/pad-to 6144k/g" target/linux/qualcommax/image/ipq60xx.mk

# samba 解除 root 限制
# sed -i 's/invalid users = root/#&/g' feeds/packages/net/samba4/files/smb.conf.template

# 调整插件显示位置
# sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
# sed -i 's/services/nas/g' feeds/luci/applications/luci-app-openlist/root/usr/share/luci/menu.d/luci-app-openlist.json
# sed -i 's/services/nas/g' feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json
# sed -i 's/services/nas/g' feeds/luci/applications/luci-app-hd-idle/root/usr/share/luci/menu.d/luci-app-hd-idle.json
# sed -i 's/services/nas/g' feeds/luci/applications/luci-app-minidlna/root/usr/share/luci/menu.d/luci-app-minidlna.json
# sed -i 's/services/control/g' feeds/luci/applications/luci-app-eqos/root/usr/share/luci/menu.d/luci-app-eqos.json
# sed -i 's/services/control/g' feeds/luci/applications/luci-app-wol/root/usr/share/luci/menu.d/luci-app-wol.json
# sed -i 's/services/control/g' feeds/luci/applications/luci-app-wifischedule/root/usr/share/luci/menu.d/luci-app-wifischedule.json

# 取消 bootstrap 为默认主题，添加 argon 主题设置为默认
rm -rf feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config

# sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' ./feeds/luci/collections/luci/Makefile

# 更新 golang 依赖（ mosdns & alist )
# rm -rf feeds/packages/lang/golang
# git clone --depth=1 -b 25.x https://github.com/sbwml/packages_lang_golang.git  feeds/packages/lang/golang

# 替换 geodata 依赖
# rm -rf feeds/packages/net/v2ray-geodata
# git clone --depth=1 https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# adguardhome
# rm -rf feeds/packages/net/adguardhome
# rm -rf feeds/luci/applications/luci-app-adguardhome
# git clone --depth=1 -b lua https://github.com/sirpdboy/luci-app-adguardhome package/luci-app-adguardhome
# git clone --depth=1 https://github.com/xptsp/luci-app-adguardhome package/luci-app-adguardhome
# git clone --depth=1 https://github.com/kongfl888/luci-app-adguardhome package/luci-app-adguardhome
# git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome

# mosdns
# rm -rf feeds/packages/net/mosdns
# rm -rf feeds/luci/applications/luci-app-mosdns
# git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns

# smartdns
# rm -rf feeds/packages/net/smartdns
# rm -rf feeds/luci/applications/luci-app-smartdns
# git clone --depth=1 https://github.com/pymumu/openwrt-smartdns.git  feeds/packages/net/smartdns
# git clone --depth=1 https://github.com/pymumu/luci-app-smartdns.git feeds/luci/applications/luci-app-smartdns
# git clone --depth=1 -b lede https://github.com/pymumu/luci-app-smartdns.git feeds/luci/applications/luci-app-smartdns

# openclash（ dev 版 ）( Mihomo Kernel )
# rm -rf feeds/luci/applications/luci-app-openclash
# git clone --depth=1 -b dev https://github.com/vernesong/OpenClash.git package/luci-app-openclash
# git clone -b master https://github.com/vernesong/OpenClash.git package/luci-app-openclash

# homeproxy ( SingBox Kernel )
# rm -rf feeds/luci/applications/luci-app-homeproxy
# git clone --depth=1 -b dev https://github.com/immortalwrt/homeproxy.git package/luci-app-homeproxy

# passwall(2) ( SingBox & Xray Kernel )
# 移除 openwrt feeds 过时的luci版本
# rm -rf feeds/luci/applications/luci-app-passwall
# rm -rf feeds/luci/applications/luci-app-passwall2
# git clone --depth=1 -b main https://github.com/xiaorouji/openwrt-passwall.git package/luci-app-passwall
# git clone --depth=1 -b main https://github.com/xiaorouji/openwrt-passwall2.git package/luci-app-passwall2

# 移除 openwrt feeds 自带的核心库
# rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box}
# rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
# git clone --depth=1 -b main https://github.com/xiaorouji/openwrt-passwall-packages.git package/passwall-packages

# nikki( Mihomo Kernel )
# git clone https://github.com/nikkinikki-org/OpenWrt-nikki.git package/luci-app-nikki
# git clone --depth=1 -b main https://github.com/nikkinikki-org/OpenWrt-nikki.git package/luci-app-nikki

# momo ( SingBox Kernel )
# git clone --depth=1 -b main https://github.com/nikkinikki-org/OpenWrt-momo.git package/luci-app-momo

# fchomo( Mihomo Kernel )
# git clone --depth=1 -b master https://github.com/fcshark-org/openwrt-fchomo.git package/openwrt-fchomo

# nekobox( SingBox Kernel )
# git clone --depth=1 -b main https://github.com/Thaolga/openwrt-nekobox.git package/openwrt-nekobox

# neko( SingBox Kernel )
# git clone --depth=1 -b main https://github.com/nosignals/openwrt-neko.git -b main package/openwrt-neko

# daed
# rm -rf feeds/packages/net/daed
# rm -rf feeds/luci/applications/luci-app-daed
# git clone --depth=1 -b main https://github.com/QiuSimons/luci-app-daed.git package/luci-app-daed

# 科学插件大全，移除 openwrt feeds 自带的核心包
# rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box}
# git clone --depth=1 https://github.com/sbwml/openwrt_helloworld.git package/helloworld

# openlist
# rm -rf feeds/packages/net/openlist
# rm -rf feeds/luci/applications/luci-app-openlist
# git clone --depth=1 https://github.com/sbwml/luci-app-openlist2.git package/luci-app-openlist2

# filemanager（ 文件管理 ）
git clone --depth=1 https://github.com/sbwml/luci-app-filemanager package/luci-app-filemanager
# git clone --depth=1 https://github.com/muink/luci-app-tinyfilemanager package/luci-app-tinyfilemanager

# jdCloud ax6600 led screen ctrl
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led

./scripts/feeds update -a
./scripts/feeds install -a
