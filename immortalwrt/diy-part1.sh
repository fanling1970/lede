#!/bin/sh
# ==========================================================
# ImmortalWrt DIY 脚本（适配 JDCloud 雅典娜 IPQ60xx）
# 功能：
# 1. Docker 根目录软链接到外置存储（依赖系统自动挂载 /mnt/mmcblk0p27）
# 2. Docker 防火墙热插拔适配（解决 Compose 网络不通/双 docker zone 问题）
# 3. 温度读取适配（修复 6.18.41+ 上游源码节点迁移导致的首页温度不显示问题）
# ==========================================================

# ------------------------------
# 1. Docker 根目录固化（无挂载逻辑，依赖系统自动挂载）
# ------------------------------
echo "--- 固化 Docker 根目录软链接 ---"
mkdir -p files/etc/rc.d
cat > files/etc/rc.d/S19docker-link << 'EOF'
#!/bin/sh /etc/rc.common
START=19
boot() {
    # 系统已自动挂载 /mnt/mmcblk0p27，直接创建软链接
    if [ -d "/mnt/mmcblk0p27" ] && [ ! -L "/opt/docker" ]; then
        # 清理默认目录避免冲突
        [ -d "/opt/docker" ] && rm -rf /opt/docker
        mkdir -p /mnt/mmcblk0p27/docker
        ln -sf /mnt/mmcblk0p27/docker /opt/docker
        logger -t docker-link "Docker 根目录已链接到 /mnt/mmcblk0p27/docker"
    fi
}
EOF
chmod +x files/etc/rc.d/S19docker-link

# ------------------------------
# 2. Docker 防火墙热插拔脚本（解决双 zone/Compose 不通问题）
# ------------------------------
echo "--- 植入 Docker 防火墙热插拔脚本 ---"
mkdir -p files/etc/hotplug.d/net
cat > files/etc/hotplug.d/net/00-docker-firewall << 'EOF'
#!/bin/sh
# 仅处理 Docker 相关网桥（docker0/br-*）
if echo "$INTERFACE" | grep -Eq "^(docker0|br-)"; then
    logger -t docker-firewall "检测到 Docker 接口 $INTERFACE，开始配置防火墙..."
    sleep 2

    # 删除所有旧 docker zone（避免 luci-app-dockerman 重复创建）
    uci show firewall | grep "option name='docker'" | while read -r line; do
        ZONE=$(echo "$line" | cut -d. -f2 | cut -d= -f1)
        uci delete firewall.$ZONE
    done

    # 新建标准 docker zone
    uci set firewall.docker=zone
    uci set firewall.docker.name='docker'
    uci set firewall.docker.input='REJECT'
    uci set firewall.docker.forward='REJECT'
    uci set firewall.docker.output='ACCEPT'
    uci set firewall.docker.masq='1'
    uci set firewall.docker.mtu_fix='1'
    uci add_list firewall.docker.device="$INTERFACE"

    # 转发规则：LAN→Docker / Docker→WAN
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest='docker'
    
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='docker'
    uci set firewall.@forwarding[-1].dest='wan'

    uci commit firewall
    /etc/init.d/firewall reload
    logger -t docker-firewall "防火墙配置完成"
fi
EOF
chmod +x files/etc/hotplug.d/net/00-docker-firewall

# ------------------------------
# 3. 手动温度查询脚本（SSH 用，多路径兜底）
# ------------------------------
echo "--- 植入 CPU 温度查询脚本 ---"
mkdir -p files/usr/bin
cat > files/usr/bin/get_cpu_temp << 'EOF'
#!/bin/sh
TEMP=0
SOURCE=""

# 优先读 6.18.41+ 的 IPQ60xx CPU 温度节点
if [ -r "/sys/class/thermal/thermal_zone1/temp" ]; then
    raw_temp=$(cat "/sys/class/thermal/thermal_zone1/temp")
    if [ "$raw_temp" -gt 1000 ]; then
        TEMP=$(( raw_temp / 1000 ))
        SOURCE="TZ1"
    fi
fi

# 兜底读旧版本节点
if [ "$TEMP" -eq 0 ] && [ -r "/sys/class/thermal/thermal_zone0/temp" ]; then
    raw_temp=$(cat "/sys/class/thermal/thermal_zone0/temp")
    if [ "$raw_temp" -gt 1000 ]; then
        TEMP=$(( raw_temp / 1000 ))
        SOURCE="TZ0"
    fi
fi

if [ "$TEMP" -gt 0 ]; then
    echo "CPU ${TEMP}°C (${SOURCE})"
else
    echo "CPU N/A"
fi
EOF
chmod +x files/usr/bin/get_cpu_temp

# ------------------------------
# 4. 温度前端适配补丁（修复 6.18.41+ 首页/Luci 状态页不显示温度问题）
# 原因：上游源码将 IPQ60xx CPU 温度节点从 thermal_zone0 迁移到 thermal_zone1，前端未同步
# ------------------------------
echo "--- 固化 Luci/Argon 温度路径适配补丁 ---"

# 4.1 修复 Luci 状态页温度读取
mkdir -p files/usr/lib/lua/luci/system
cat > files/usr/lib/lua/luci/system/status.lua << 'EOF'
module("luci.system.status", package.seeall)

function get_cpu_temp()
    local temp = nil
    -- 优先读取 6.18.41+ 的 IPQ60xx 温度节点
    local f = io.open("/sys/class/thermal/thermal_zone1/temp", "r")
    if f then
        temp = f:read("*n")
        f:close()
        if temp and temp > 1000 then
            return string.format("%.1f°C", temp / 1000)
        end
    end
    -- 兜底读取旧版本节点
    f = io.open("/sys/class/thermal/thermal_zone0/temp", "r")
    if f then
        temp = f:read("*n")
        f:close()
        if temp and temp > 1000 then
            return string.format("%.1f°C", temp / 1000)
        end
    end
    return "N/A"
end
EOF

# 4.2 修复 Argon 主题首页温度读取
mkdir -p files/www/luci-static/argon/js
cat > files/www/luci-static/argon/js/argon.js << 'EOF'
// 适配 IPQ60xx 6.18.41+ 温度读取
function getCpuTemp() {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", "/cgi-bin/luci/admin/status/cpu_temp", false);
    xhr.send();
    if (xhr.status === 200 && xhr.responseText !== "N/A") {
        return xhr.responseText;
    }
    // 兜底读取 sysfs
    var xhr2 = new XMLHttpRequest();
    xhr2.open("GET", "/sys/class/thermal/thermal_zone1/temp", false);
    xhr2.send();
    if (xhr2.status === 200 && xhr2.responseText > 1000) {
        return (xhr2.responseText / 1000).toFixed(1) + "°C";
    }
    // 旧路径兜底
    xhr2.open("GET", "/sys/class/thermal/thermal_zone0/temp", false);
    xhr2.send();
    if (xhr2.status === 200 && xhr2.responseText > 1000) {
        return (xhr2.responseText / 1000).toFixed(1) + "°C";
    }
    return "N/A";
}
EOF

# 4.3 添加 CGI 接口（让前端稳定读取温度，避免权限问题）
mkdir -p files/www/cgi-bin/luci/admin/status
cat > files/www/cgi-bin/luci/admin/status/cpu_temp << 'EOF'
#!/bin/sh
echo "Content-type: text/plain"
echo ""
# 优先读 6.18.41+ 节点
if [ -r "/sys/class/thermal/thermal_zone1/temp" ]; then
    raw=$(cat /sys/class/thermal/thermal_zone1/temp)
    if [ "$raw" -gt 1000 ]; then
        echo "$((raw / 1000)).$(( (raw / 100) % 10 ))°C"
        exit 0
    fi
fi
# 兜底读旧节点
if [ -r "/sys/class/thermal/thermal_zone0/temp" ]; then
    raw=$(cat /sys/class/thermal/thermal_zone0/temp)
    if [ "$raw" -gt 1000 ]; then
        echo "$((raw / 1000)).$(( (raw / 100) % 10 ))°C"
        exit 0
    fi
fi
echo "N/A"
EOF
chmod +x files/www/cgi-bin/luci/admin/status/cpu_temp

echo "✅ 所有固化脚本植入完成，刷机后自动生效"
