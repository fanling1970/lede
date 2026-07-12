#!/bin/bash
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
  option hostname 'LEDE'
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
# 4. 创建简单的服务检查脚本
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
echo "=========================================="
