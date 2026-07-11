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
# 修改 device 设备名称
sed -i "s/hostname='.*'/hostname='LIBWRT'/g" package/base-files/files/bin/config_generate
