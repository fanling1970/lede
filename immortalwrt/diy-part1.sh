#!/bin/sh
# ==========================================================
# ImmortalWrt DIY 脚本（适配 JDCloud 雅典娜 IPQ60xx）
# 版本：最终无坑版
#
# 包含功能：
# 1. Docker 根目录软链接到外置存储（依赖系统自动挂载）
# 2. Docker 防火墙热插拔适配（解决双 zone / Compose 不通）
# 3. CPU 温度读取脚本（SSH 用，多路径兜底）
# 4. Luci 状态页温度适配（修复 6.18.41+ 节点迁移）
# 5. Argon 主题首页温度适配（CGI 接口，不碰系统文件）
#
# 红线规则（已遵守）：
# - 绝不创建 /www/cgi-bin/luci 目录（OpenWrt 编译红线）
# - 绝不覆盖系统自带 cpuinfo 命令
# - 所有 CGI 接口放在独立路径下
# ==========================================================

# ------------------------------
# 0. 清理旧残留（防止文件/目录冲突导致编译失败）
# ------------------------------
echo "--- 清理旧的温度补丁残留 ---"
rm -rf files/www/cgi-bin/luci
rm -f files/www/cgi-bin/cpu_temp
rm -f files/usr/bin/get_cpu_temp
rm -f files/usr/lib/lua/luci/system/status.lua
rm -f files/www/luci-static/argon/js/argon.js

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
# 2. Docker 防火墙热插拔脚本（解决双 zone / Compose 不通）
# ------------------------------
echo "--- 植入 Docker 防火墙热插拔脚本 ---"
mkdir -p files/etc/hotplug.d/net
cat > files/etc/hotplug.d/net/00-docker-firewall << 'EOF'
#!/bin/sh
# 仅处理 Docker 相关网桥（docker0 / br-*）
if echo "$INTERFACE" | grep -Eq "^(docker0|br-)"; then
    logger -t docker-firewall "检测到 Docker 接口 $INTERFACE，开始配置防火墙..."
    sleep 3

    # 删除所有旧 docker zone（防止 luci-app-dockerman 重复创建）
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

    # 转发规则：LAN → Docker
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest='docker'

    # 转发规则：Docker → WAN
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
# 3. SSH 温度查询脚本（多路径兜底，不覆盖系统命令）
# ------------------------------
echo "--- 植入 CPU 温度查询脚本 ---"
mkdir -p files/usr/bin
cat > files/usr/bin/get_cpu_temp << 'EOF'
#!/bin/sh
# 适配 JDCloud 雅典娜 (IPQ60xx) CPU 温度读取
# 多路径兜底：兼容 6.18.39 / 6.18.41+ 及未来变更

TEMP=0
SOURCE=""

# 路径1：6.18.41+ IPQ60xx 常用 CPU 温度传感器
if [ -r "/sys/class/thermal/thermal_zone1/temp" ]; then
    raw_temp=$(cat "/sys/class/thermal/thermal_zone1/temp")
    if [ "$raw_temp" -gt 1000 ]; then
        TEMP=$(( raw_temp / 1000 ))
        SOURCE="TZ1"
    fi
fi

# 路径2：传统 thermal_zone0（6.18.39 及更早版本）
if [ "$TEMP" -eq 0 ] && [ -r "/sys/class/thermal/thermal_zone0/temp" ]; then
    raw_temp=$(cat "/sys/class/thermal/thermal_zone0/temp")
    if [ "$raw_temp" -gt 1000 ]; then
        TEMP=$(( raw_temp / 1000 ))
        SOURCE="TZ0"
    fi
fi

# 路径3：通用 hwmon 传感器（极端兜底）
if [ "$TEMP" -eq 0 ] && [ -r "/sys/class/hwmon/hwmon0/temp1_input" ]; then
    raw_temp=$(cat "/sys/class/hwmon/hwmon0/temp1_input")
    if [ "$raw_temp" -gt 1000 ]; then
        TEMP=$(( raw_temp / 1000 ))
        SOURCE="HWMon0"
    fi
fi

# 输出结果
if [ "$TEMP" -gt 0 ]; then
    echo "CPU ${TEMP}°C (${SOURCE})"
else
    echo "CPU N/A"
fi
EOF
chmod +x files/usr/bin/get_cpu_temp

# ------------------------------
# 4. Luci 状态页温度适配（修复 6.18.41+ 节点迁移）
# ------------------------------
echo "--- 固化 Luci 状态页温度适配补丁 ---"
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

# ------------------------------
# 5. Argon 主题首页温度适配（CGI 接口，不碰系统文件）
# ------------------------------
echo "--- 固化 Argon 主题温度适配补丁 ---"

# 5.1 CGI 接口（独立路径，绝不碰 /www/cgi-bin/luci）
mkdir -p files/www/cgi-bin
cat > files/www/cgi-bin/cpu_temp << 'EOF'
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
    raw=$(cat /sys/class/thermal/thermal_zone0/temp")
    if [ "$raw" -gt 1000 ]; then
        echo "$((raw / 1000)).$(( (raw / 100) % 10 ))°C"
        exit 0
    fi
fi

echo "N/A"
EOF
chmod +x files/www/cgi-bin/cpu_temp

# 5.2 Argon JS 补丁（通过 CGI 接口读取，不读 sysfs 原文）
mkdir -p files/www/luci-static/argon/js
cat > files/www/luci-static/argon/js/argon.js << 'EOF'
// 适配 IPQ60xx 6.18.41+ 温度读取（通过 CGI 接口，稳定可靠）
(function() {
    var origGetCpuTemp = window.getCpuTemp;
    window.getCpuTemp = function() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "/cgi-bin/cpu_temp", false);
        xhr.send();
        if (xhr.status === 200 && xhr.responseText !== "N/A") {
            return xhr.responseText;
        }
        // 兜底：调用原始函数
        if (typeof origGetCpuTemp === "function") {
            return origGetCpuTemp();
        }
        return "N/A";
    };
})();
EOF

echo "✅ 所有固化脚本植入完成，刷机后自动生效"
