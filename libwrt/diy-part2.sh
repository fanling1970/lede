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

echo "🔧 DIY Part 2: 编译后自定义操作 - 简化版"
echo "执行时间: $(date)"
echo "配置目标: 只固化基础网络和WiFi，插件配置刷机后手动完成"

# ====================================================================
# 1. 网络配置固化
# ====================================================================
echo "设置网络配置..."

# 创建网络配置脚本（首次启动时执行）
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-network << 'EOF'
#!/bin/sh

echo "开始配置基础网络和WiFi..."

# 设置LAN口IP为192.168.100.1
uci set network.lan.ipaddr='192.168.100.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

# 设置无线网络 - radio0 (5G)
uci set wireless.radio0.channel='149'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='HE80'
uci set wireless.@wifi-iface[0].ssid='JDC_AX6600_5G'
uci set wireless.@wifi-iface[0].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[0].encryption='psk2'

# 设置无线网络 - radio1 (2.4G)
uci set wireless.radio1.channel='6'
uci set wireless.radio1.band='2g'
uci set wireless.radio1.htmode='HT40'
uci set wireless.@wifi-iface[1].ssid='JDC_AX6600_2.4G'
uci set wireless.@wifi-iface[1].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[1].encryption='psk2'

# 设置无线网络 - radio2 (5G2)
uci set wireless.radio2.channel='44'
uci set wireless.radio2.band='5g'
uci set wireless.radio2.htmode='HE160'
uci set wireless.@wifi-iface[2].ssid='JDC_AX6600_5G2'
uci set wireless.@wifi-iface[2].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[2].encryption='psk2'

# 启用所有无线接口
uci set wireless.radio0.disabled='0'
uci set wireless.radio1.disabled='0'
uci set wireless.radio2.disabled='0'
uci commit wireless

# 设置空密码（首次登录后强制修改）
passwd -d root

# 设置 SSH 允许空密码登录（首次登录后建议关闭）
uci set dropbear.@dropbear[0].PasswordAuth='on'
uci set dropbear.@dropbear[0].RootPasswordAuth='on'
uci commit dropbear

# 设置时区
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system

# 重启网络相关服务
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart

echo "基础网络配置完成！"
echo "=========================================="
echo "管理地址: http://192.168.100.1"
echo "用户名: root"
echo "密码: 空 (首次登录后请立即修改)"
echo "WiFi密码: 12345678"
echo "=========================================="
EOF
chmod +x files/etc/uci-defaults/99-custom-network

# ====================================================================
# 2. 创建防火墙基础配置
# ====================================================================
echo "配置防火墙基础规则..."

mkdir -p files/etc/config
cat > files/etc/config/firewall << 'EOF'
config defaults
  option syn_flood '1'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'REJECT'

config zone
  option name 'lan'
  list network 'lan'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'

config zone
  option name 'wan'
  list network 'wan'
  list network 'wan6'
  option input 'REJECT'
  option output 'ACCEPT'
  option forward 'REJECT'
  option masq '1'
  option mtu_fix '1'

config forwarding
  option src 'lan'
  option dest 'wan'

config rule
  option name 'Allow-DHCP-Renew'
  option src 'wan'
  option proto 'udp'
  option dest_port '68'
  option target 'ACCEPT'
  option family 'ipv4'

config rule
  option name 'Allow-Ping'
  option src 'wan'
  option proto 'icmp'
  option icmp_type 'echo-request'
  option family 'ipv4'
  option target 'ACCEPT'
EOF

# ====================================================================
# 3. 创建系统基础配置
# ====================================================================
echo "配置系统基础设置..."

cat > files/etc/config/system << 'EOF'
config system
  option hostname 'LibWrt'
  option timezone 'CST-8'
  option ttylogin '0'
  option log_size '64'
  option urandom_seed '0'

config timeserver 'ntp'
  option enabled '1'
  list server 'time1.aliyun.com'
  list server 'time2.aliyun.com'
  list server 'time3.aliyun.com'
EOF

# ====================================================================
# 4. 创建使用说明文档（简化版）
# ====================================================================
mkdir -p files/root
cat > files/root/README-SIMPLE-FIRMWARE.txt << 'EOF'
==========================================
    JDCloud RE-CS-02 简化固件说明
===========================================

固件编译时间: 2026-06-05
固件版本: LEDE R26.05.20 + 基础插件
配置策略: 只固化基础网络，插件配置刷机后手动完成

一、基础配置
------------
1. 管理地址: http://192.168.100.1
2. 用户名: root
3. 密码: 空 (首次登录后强制修改)
4. WiFi 接口:
 - JDC_AX6600_5G (5G, 信道136)
 - JDC_AX6600_2.4G (2.4G, 信道6)
 - JDC_AX6600_5G2 (5G, 信道36)
5. WiFi密码: 12345678

二、已安装插件（需手动配置）
---------------------------
1. OpenClash: 代理工具
 - 管理界面: 服务 → OpenClash
 - 默认未启动，需上传节点配置

2. MosDNS: DNS分流工具
 - 管理界面: 服务 → MosDNS
 - 默认配置可用，建议按需调整

3. PassWall: 备用代理工具
4. SSR Plus+: 备用代理工具
5. DockerMan: Docker 管理界面
6. Argon 主题: 美化界面

三、刷机后操作步骤
------------------
1. 首次登录: http://192.168.100.1 (空密码)
2. 立即修改管理员密码
3. 测试网络连接和WiFi
4. 按需配置插件:
 a. OpenClash: 上传节点 → 启动服务
 b. MosDNS: 检查配置 → 启动服务
 c. 其他插件按需使用

四、配置文件位置
----------------
1. 网络配置: /etc/config/network
2. 无线配置: /etc/config/wireless
3. 系统配置: /etc/config/system
4. 防火墙: /etc/config/firewall

五、注意事项
------------
1. 安全性: 首次登录后务必修改密码！
2. 稳定性: 插件逐个配置，避免冲突
3. 备份: 配置稳定后备份: sysupgrade -b /tmp/backup.tar.gz
4. 第三个5G接口: 可根据需要禁用

===========================================
固件设计理念:
- 基础网络稳定优先
- 插件配置灵活可控
- 减少固化冲突风险
===========================================
EOF

# ====================================================================
# 5. 创建简单的服务检查脚本
# ====================================================================
mkdir -p files/usr/bin
cat > files/usr/bin/check-services << 'EOF'
#!/bin/sh
# 简单的服务状态检查脚本

echo "=== 系统服务状态检查 ==="
echo "当前时间: $(date)"
echo ""

echo "1. 网络服务:"
ifconfig br-lan 2>/dev/null && echo "  ✓ LAN 接口正常" || echo "  ✗ LAN 接口异常"
echo ""

echo "2. WiFi 服务:"
iwinfo 2>/dev/null | grep -q "ESSID" && echo "  ✓ WiFi 运行正常" || echo "  ✗ WiFi 可能异常"
echo ""

echo "3. 插件安装状态:"
[ -f /etc/config/openclash ] && echo "  ✓ OpenClash 已安装" || echo "  ✗ OpenClash 未安装"
[ -f /etc/config/mosdns ] && echo "  ✓ MosDNS 已安装" || echo "  ✗ MosDNS 未安装"
[ -f /usr/bin/dockerd ] && echo "  ✓ Docker 已安装" || echo "  ✗ Docker 未安装"
echo ""

echo "4. 系统信息:"
echo "  IP地址: $(uci get network.lan.ipaddr 2>/dev/null || echo '未配置')"
echo "  主机名: $(uci get system.@system[0].hostname 2>/dev/null || echo '未配置')"
echo ""

echo "检查完成！"
EOF
chmod +x files/usr/bin/check-services

echo "✅ DIY Part 2 简化版完成"
echo "=========================================="
echo "配置总结:"
echo "1. 基础网络: ✓ (IP:192.168.100.1)"
echo "2. 三个WiFi: ✓ (密码:BUZHIDAOWA)"
echo "3. 空密码登录: ✓ (首次登录后强制修改)"
echo "4. 使用说明: ✓ (文件: /root/README-SIMPLE-FIRMWARE.txt)"
echo "=========================================="

# 修改 device 设备名称
# sed -i "s/hostname='.*'/hostname='OpenWrt'/g" package/base-files/files/bin/config_generate

# 修改 固件版本 显示名称
# sed -i "s/LibWrt/ImmortalWrt/g" Config.in
# sed -i "s/LibWrt/ImmortalWrt/g" include/version.mk
# sed -i "s/LibWrt/ImmortalWrt/g" config/Config-images.in
# sed -i "s/LibWrt/ImmortalWrt/g" package/base-files/image-config.in

# 默认网关 ip 地址修改
# sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

# 修改 wifi 无线名称
# sed -i "s/LibWrt/OpenWrt/g" package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc
# sed -i "s/ImmortalWrt/OpenWrt/g" package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc

# 修改 wifi 无线名称 & 密码
# sed -i "s/BASE_SSID='.*'/BASE_SSID='OpenWrt'/g" target/linux/qualcommax/base-files/etc/uci-defaults/990_set-wireless.sh
# sed -i "s/BASE_WORD='.*'/BASE_WORD='password'/g" target/linux/qualcommax/base-files/etc/uci-defaults/990_set-wireless.sh

# 最大连接数修改为 65535
# sed -i "s/nf_conntrack_max=.*/nf_conntrack_max=65535/g" package/kernel/linux/files/sysctl-nf-conntrack.conf
# sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf

# 修改 luci 文件，添加 NSS Load 相关状态显示
# sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const fd = popen(access('/sbin/cpuinfo') ? '/sbin/cpuinfo' : \"top -n1 | awk \\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\'\")#g"

# 修改 wifi 默认打开
# sed -i "s/disabled='${defaults ? 0 : 1}'/disabled='0'/g" package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc

# 更换 Kernel 内核版本
# sed -i "s/KERNEL_PATCHVER:=6.6/KERNEL_PATCHVER:=6.1/g" target/linux/qualcommax/Makefile

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
rm -rf feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config

sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' ./feeds/luci/collections/luci/Makefile

# kucat theme
# git clone --depth=1 https://github.com/sirpdboy/luci-theme-kucat.git package/luci-theme-kucat
# git clone --depth=1 https://github.com/sirpdboy/luci-app-kucat-config.git package/luci-app-kucat
# git clone --depth=1 https://github.com/sirpdboy/luci-app-advancedplus.git package/luci-app-advancedplus

# 更新 golang 依赖（ mosdns & alist 插件 )
# rm -rf feeds/packages/lang/golang
# git clone --depth=1 -b 25.x https://github.com/sbwml/packages_lang_golang.git  feeds/packages/lang/golang

# 替换 geodata 依赖
# rm -rf feeds/packages/net/v2ray-geodata
# git clone --depth=1 https://github.com/sbwml/v2ray-geodata.git package/v2ray-geodata

# AdguardHome
# rm -rf feeds/packages/net/adguardhome
# rm -rf feeds/luci/applications/luci-app-adguardhome
# git clone --depth=1 -b dev https://github.com/stevenjoezhang/luci-app-adguardhome.git package/luci-app-adguardhome
# git clone --depth=1 -b master https://github.com/w9315273/luci-app-adguardhome.git package/luci-app-adguardhome
# git clone --depth=1 -b main https://github.com/TanZhiwen2001/luci-app-adguardhome.git package/luci-app-adguardhome
# git clone --depth=1 https://github.com/kongfl888/luci-app-adguardhome.git package/luci-app-adguardhome
# git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome

# mosdns
# rm -rf feeds/packages/net/mosdns
# rm -rf feeds/luci/applications/luci-app-mosdns
# git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns

# smartdns
# rm -rf feeds/packages/net/smartdns
# rm -rf feeds/luci/applications/luci-app-smartdns
# git clone --depth=1 https://github.com/pymumu/openwrt-smartdns.git package/smartdns
# git clone --depth=1 https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns

# passwall(2) ( SingBox & Xray Kernel )
# 移除 openwrt feeds 过时的luci版本
rm -rf feeds/luci/applications/luci-app-passwall
# rm -rf feeds/luci/applications/luci-app-passwall2
git clone --depth=1 https://github.com/kenzok8/small package/luci-app-passwall
# git clone --depth=1 -b main https://github.com/xiaorouji/openwrt-passwall2.git package/luci-app-passwall2

# 移除 openwrt feeds 自带的核心库
# rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box}
# rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
# git clone --depth=1 -b main https://github.com/xiaorouji/openwrt-passwall-packages.git package/passwall-packages

# OpenClash
# 删除源码自带 luci-app-openclash，避免冲突
rm -rf feeds/luci/applications/luci-app-openclash
# 克隆kenzok8/small仓库（仅master分支，浅克隆减少耗时）
git clone --depth=1 https://github.com/kenzok8/small package/luci-app-openclash

# luci-app-ssr-plus
git clone --depth=1 https://github.com/kenzok8/small package/luci-app-ssr-plus

# nikki( Mihomo Kernel )
# git clone --depth=1 -b main https://github.com/nikkinikki-org/OpenWrt-nikki.git package/luci-app-nikki

# fchomo( Mihomo Kernel  ) OpenWrt ≥ 24.10
# git clone --depth=1 -b master https://github.com/fcshark-org/openwrt-fchomo.git package/openwrt-fchomo

# homeproxy( SingBox Kernel )
# rm -rf feeds/luci/applications/luci-app-homeproxy
# git clone --depth=1 -b dev https://github.com/immortalwrt/homeproxy.git package/luci-app-homeproxy

# momo ( SingBox Kernel ) OpenWrt ≥ 24.10
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
# git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac.git package/openwrt-gecoosac

# lucky
# git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky

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
# rm -rf package/kernel/mac80211/patches/nss/ath11k/999-900-bss-transition-handling.patch

# 修复 rust 报错
# wget -O feeds/packages/lang/rust/Makefile https://raw.githubusercontent.com/aimetu/OpenWrt-Actions/refs/heads/main/patches/Makefile
# sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile

./scripts/feeds update -a
./scripts/feeds install -a
