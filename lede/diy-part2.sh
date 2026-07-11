#!/bin/bash
echo "🔧 DIY Part 2: 编译后自定义操作 - AX6600 专用版"
echo "执行时间: $(date)"
echo "配置目标: 固化基础网络/WiFi/密码，反制QuickStart默认配置"

# ====================================================================
# 0. 提前解决首次启动SSH连不上问题（延后Dropbear启动顺序）
# ====================================================================
echo "优化Dropbear启动顺序，解决首次启动SSH无法连接问题..."
if [ -f /etc/init.d/dropbear ]; then
    # 把Dropbear启动顺序从默认的60改成95，等NSS/网络完全初始化后再启动
    sed -i 's/START=60/START=95/g' /etc/init.d/dropbear
    echo "✅ Dropbear启动顺序已调整为95，首次启动可直接SSH连接"
fi

# ====================================================================
# 1. 网络&无线配置固化（最后执行，覆盖所有默认配置）
# ====================================================================
echo "设置基础网络与三频WiFi配置..."

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-network << 'EOF'
#!/bin/sh
exec > /tmp/uci-defaults.log 2>&1

echo "====== 开始固化AX6600基础配置 ======"

# --------------------------
# 1.1 有线网络配置
# --------------------------
uci set network.lan.ipaddr='192.168.100.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network
echo "✅ LAN口IP已设置为192.168.100.1"

# --------------------------
# 1.2 三频无线配置（AX6600专用）
# --------------------------
# Radio0: 第一路5G（IPQ6018内置）
uci set wireless.radio0.channel='149'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='HE80'
uci set wireless.radio0.disabled='0'

# Radio1: 2.4G（IPQ6018内置）
uci set wireless.radio1.channel='6'
uci set wireless.radio1.band='2g'
uci set wireless.radio1.htmode='HT40'
uci set wireless.radio1.disabled='0'

# Radio2: 第二路5G（QCN9074独立第三频）
uci set wireless.radio2.channel='44'
uci set wireless.radio2.band='5g'
uci set wireless.radio2.htmode='HE160'
uci set wireless.radio2.disabled='0'

# WiFi SSID/密码配置（三个频段统一密码）
# 5G-1
uci set wireless.@wifi-iface[0].ssid='JDC_AX6600_5G'
uci set wireless.@wifi-iface[0].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[0].encryption='psk2'
uci set wireless.@wifi-iface[0].disabled='0'

# 2.4G
uci set wireless.@wifi-iface[1].ssid='JDC_AX6600_2.4G'
uci set wireless.@wifi-iface[1].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[1].encryption='psk2'
uci set wireless.@wifi-iface[1].disabled='0'

# 5G-2（第三频，QCN9074）
uci set wireless.@wifi-iface[2].ssid='JDC_AX6600_5G2'
uci set wireless.@wifi-iface[2].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[2].encryption='psk2'
uci set wireless.@wifi-iface[2].disabled='0'

uci commit wireless
echo "✅ 三频WiFi配置完成（密码统一为BUZHIDAOWA）"

# --------------------------
# 1.3 账号密码配置（反制QuickStart覆盖）
# --------------------------
# 统一root密码为BUZHIDAOWA（覆盖QuickStart默认密码）
echo 'root:BUZHIDAOWA' | chpasswd
echo "✅ root密码已固化：BUZHIDAOWA"

# SSH允许密码登录
uci set dropbear.@dropbear[0].PasswordAuth='on'
uci set dropbear.@dropbear[0].RootPasswordAuth='on'
uci commit dropbear

# 修复LuCI(rpcd)登录配置，确保网页端能使用系统密码登录（反制QuickStart改动）
if [ -f /etc/config/rpcd ]; then
    uci -q delete rpcd.@login[0]
    uci set rpcd._login=rpcd login
    uci set rpcd.@login[-].username='root'
    # $p$root表示使用/etc/shadow中的系统密码
    uci add_list rpcd.@login[-].password='$p$root'
    uci commit rpcd
    echo "✅ LuCI登录已配置为使用系统密码"
fi

# --------------------------
# 1.4 系统时区与NTP
# --------------------------
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].hostname='JDC-AX6600'
# 阿里云NTP服务器
uci -q delete system.ntp.server
uci add_list system.ntp.server='time1.aliyun.com'
uci add_list system.ntp.server='time2.aliyun.com'
uci add_list system.ntp.server='time3.aliyun.com'
uci set system.ntp.enabled='1'
uci commit system
echo "✅ 时区与NTP配置完成"

# ❌ 禁止在uci-defaults阶段重启服务，系统首次启动会自动应用配置
# （原重启命令会导致WiFi/网络反复上下线，已移除）

echo "====== 基础配置固化完成 ======"
EOF
chmod +x files/etc/uci-defaults/99-custom-network

# ====================================================================
# 2. 防火墙基础配置（精简，仅保留必要规则）
# ====================================================================
echo "配置防火墙基础规则..."
mkdir -p files/etc/config
cat > files/etc/config/firewall << 'EOF'
config defaults
    option syn_flood         '1'
    option input             'ACCEPT'
    option output            'ACCEPT'
    option forward           'REJECT'

config zone
    option name              'lan'
    list network             'lan'
    option input             'ACCEPT'
    option output            'ACCEPT'
    option forward           'ACCEPT'

config zone
    option name              'wan'
    list network             'wan'
    list network             'wan6'
    option input             'REJECT'
    option output            'ACCEPT'
    option forward           'REJECT'
    option masq              '1'
    option mtu_fix           '1'

config forwarding
    option src               'lan'
    option dest              'wan'

# 允许WAN口DHCP续租
config rule
    option name              'Allow-DHCP-Renew'
    option src               'wan'
    option proto             'udp'
    option dest_port         '68'
    option target            'ACCEPT'
    option family            'ipv4'

# 允许WAN口Ping（方便排查网络问题）
config rule
    option name              'Allow-Ping'
    option src               'wan'
    option proto             'icmp'
    option icmp_type         'echo-request'
    option family            'ipv4'
    option target            'ACCEPT'
EOF

# ====================================================================
# 3. 系统基础配置
# ====================================================================
echo "配置系统基础设置..."
cat > files/etc/config/system << 'EOF'
config system
    option hostname          'LEDE'
    option timezone          'CST-8'
    option ttylogin          '0'
    option log_size          '64'
    option urandom_seed      '0'

config timeserver 'ntp'
    option enabled           '1'
    list server              'time1.aliyun.com'
    list server              'time2.aliyun.com'
    list server              'time3.aliyun.com'
EOF

# ====================================================================
# 4. 刷机后使用说明（修正所有错误信息，仅保留已编译插件）
# ====================================================================
mkdir -p files/root
cat > files/root/README-FIRMWARE.txt << 'EOF'
==========================================
    JDCloud RE-CS-02 雅典娜 AX6600 固件说明
===========================================

📦 固件编译时间: $(date)
📦 固件版本: LEDE de1795d + 精简插件
📦 配置策略: 基础网络固化，插件刷机后手动配置

----------------------------------------------------------
一、基础登录信息（请牢记）
----------------------------------------------------------
✅ 管理地址: http://192.168.100.1
✅ SSH地址: ssh root@192.168.100.1
✅ 用户名: root
✅ 登录密码: BUZHIDAOWA（网页/SSH通用）
✅ 首次登录后建议立即修改密码！

----------------------------------------------------------
二、WiFi信息（三个频段统一密码）
----------------------------------------------------------
1. JDC_AX6600_5G（第一路5G，信道149，HE80）
2. JDC_AX6600_2.4G（2.4G，信道6，HT40）
3. JDC_AX6600_5G2（第三频5G，信道44，HE160，QCN9074独立Radio）
✅ 所有WiFi密码: BUZHIDAOWA

----------------------------------------------------------
三、已编译插件（按需配置，默认未启动）
----------------------------------------------------------
1. 🌈 Argon主题：系统 →  Argon主题设置（已默认启用）
2. 🚀 SSR Plus+：服务 → SSR Plus+（唯一代理工具，支持全协议）
3. 🐳 DockerMan：服务 → Docker（已默认安装，需手动启动）
4. 🏪 iStore/QuickStart：服务 → 快捷启动/软件商店
5. 💡 Athena LED控制：服务 → Athena LED控制（第三频指示灯管理）

----------------------------------------------------------
四、刷机后操作步骤
----------------------------------------------------------
1. 浏览器访问 http://192.168.100.1，输入密码 BUZHIDAOWA 登录
2. 立即修改root密码：【系统】→【管理权】→【修改密码】
3. 测试WiFi：手机/电脑连接三个WiFi频段，确认能正常上网
4. 配置代理：进入【服务】→【SSR Plus+】，上传节点配置并启动
5. 配置Docker：【服务】→【Docker】，设置镜像加速并启动服务
6. 个性化设置：调整Argon主题背景、LED灯效等

----------------------------------------------------------
五、常用命令
----------------------------------------------------------
# 检查服务状态
check-services

# 备份当前配置
sysupgrade -b /tmp/backup-$(date +%Y%m%d).tar.gz

# 查看WiFi状态
iwinfo

# 查看NSS加速状态
cat /proc/net/nf_conntrack | wc -l

----------------------------------------------------------
⚠️ 注意事项
----------------------------------------------------------
1. 首次启动SSH可直接连接，无需重启路由器
2. 第三频5G2（QCN9074）支持160MHz频宽，适合游戏/NAS使用
3. 不要同时启用多个代理插件，避免规则冲突
4. 配置稳定后务必备份配置，方便后续刷机恢复

===========================================
固件设计理念:
- 基础网络100%稳定，首次启动即用
- 插件按需配置，避免冗余冲突
- 完全适配AX6600三频硬件
===========================================
EOF

# ====================================================================
# 5. 服务状态检查脚本（仅检查已编译插件）
# ====================================================================
mkdir -p files/usr/bin
cat > files/usr/bin/check-services << 'EOF'
#!/bin/sh
# AX6600专用服务状态检查脚本

echo "====== JDCloud AX6600 服务状态检查 ======"
echo "检查时间: $(date)"
echo ""

echo "【1. 基础网络状态】"
echo "LAN IP: $(uci get network.lan.ipaddr 2>/dev/null || echo '未配置')"
echo "主机名: $(uci get system.@system[0].hostname 2>/dev/null || echo '未配置')"
brctl show br-lan >/dev/null 2>&1 && echo "✅ LAN桥接正常" || echo "❌ LAN桥接异常"
echo ""

echo "【2. 三频WiFi状态】"
iwinfo | grep -q "ESSID" && echo "✅ WiFi服务运行中" || echo "❌ WiFi服务异常"
echo "5G-1: $(uci get wireless.radio0.disabled 2>/dev/null | sed 's/0/启用/;s/1/禁用/')"
echo "2.4G: $(uci get wireless.radio1.disabled 2>/dev/null | sed 's/0/启用/;s/1/禁用/')"
echo "5G-2(第三频): $(uci get wireless.radio2.disabled 2>/dev/null | sed 's/0/启用/;s/1/禁用/')"
echo ""

echo "【3. 已安装插件状态】"
[ -f /etc/config/luci-theme-argon ] && echo "✅ Argon主题已安装" || echo "❌ Argon主题未安装"
[ -f /etc/config/luci-app-ssr-plus ] && echo "✅ SSR Plus+已安装" || echo "❌ SSR Plus+未安装"
[ -f /usr/bin/dockerd ] && echo "✅ Docker已安装" || echo "❌ Docker未安装"
[ -f /etc/config/luci-app-athena-led ] && echo "✅ Athena LED控制已安装" || echo "❌ Athena LED控制未安装"
[ -f /etc/config/luci-app-quickstart ] && echo "✅ QuickStart已安装" || echo "❌ QuickStart未安装"
echo ""

echo "【4. 系统资源】"
echo "内存使用: $(free -h | awk '/Mem/{print $3"/"$2}')"
echo "存储空间: $(df -h / | awk 'NR==2{print $3"/"$2}')"
echo ""

echo "====== 检查完成 ======"
echo "详细说明请查看：/root/README-FIRMWARE.txt"
EOF
chmod +x files/usr/bin/check-services

# ====================================================================
# 6. 首次启动后自动提示（可选）
# ====================================================================
mkdir -p files/etc/profile.d
cat > files/etc/profile.d/99-welcome.sh << 'EOF'
#!/bin/sh
# 首次登录SSH时自动显示欢迎信息
if [ -t 0 ]; then
    clear
    echo "=========================================="
    echo " 欢迎使用 JDCloud AX6600 定制固件"
    echo " 管理地址: http://192.168.100.1"
    echo " 登录密码: BUZHIDAOWA"
    echo " 服务检查: 执行 check-services 查看状态"
    echo " 详细说明: cat /root/README-FIRMWARE.txt"
    echo "=========================================="
    echo ""
fi
EOF
chmod +x files/etc/profile.d/99-welcome.sh

echo "✅ DIY Part 2 配置完成"
echo "=========================================="
echo "最终配置总结:"
echo "1. 管理IP: 192.168.100.1"
echo "2. 登录密码: BUZHIDAOWA（网页/SSH通用）"
echo "3. 三频WiFi: 均已启用，密码BUZHIDAOWA"
echo "4. 首次启动SSH: 可直接连接，无需重启"
echo "5. QuickStart覆盖问题: 已反制，密码不会被修改"
echo "=========================================="
