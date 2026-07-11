#!/bin/bash
# 执行目录：openwrt 源码根目录
set -e

echo "=== [DIY-P1] 开始预处理第三方包 ==="

# ======================================
# 0. 先删 feeds/luci 里 Lean 自带的旧版 argon（关键！避免同名冲突）
# feeds install 之后 luci 的索引在 feeds/luci.index，包在 feeds/luci/themes/
# ======================================
echo "--- 清理 Lean 自带旧版 argon（防止和 jerrykuku 新版撞名） ---"
rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null || true
# 顺手也清掉 feeds 索引里可能残留的引用，防止 install -a 又捡回来
sed -i '/^Package: luci-theme-argon$/,$ {/^$/d; /^Package:/a auto-selected 0' feeds/luci.index 2>/dev/null || true
echo "✅ Lean 旧版 argon 已清除"

# ======================================
# 1. 清理 argon 残留（package/ 下如果之前拉过旧的也清掉）
# ======================================
echo "--- 清理 package/ 下 argon 旧残留 ---"
rm -rf package/luci-theme-argon package/luci-app-argon-config
echo "✅ package/ 残留清理完成"

# ======================================
# 2. 手动拉取 jerrykuku Argon 主题 + 配置插件
# ======================================
echo "--- 拉取 Argon 主题（jerrykuku 新版） ---"
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon || {
    echo "❌ Argon 主题拉取失败"
    exit 1
}

echo "--- 拉取 Argon 配置插件 ---"
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config || {
    echo "❌ Argon 配置插件拉取失败"
    exit 1
}
echo "✅ Argon 新版拉取完成"

# ======================================
# 3. 京东云 AX6600 LED 控制插件
# ======================================
echo "--- 拉取 Athena LED 控制插件 ---"
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led || {
    echo "❌ Athena LED 插件拉取失败"
    exit 1
}

chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led
chmod +x package/luci-app-athena-led/root/usr/sbin/athena-led
echo "✅ Athena LED 插件赋权完成"

# 在 diy-part1.sh 的 argon/athena 处理之后加这段
echo "--- 升级 Golang 到 1.26（适配新协议客户端） ---"
rm -rf feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
echo "✅ Golang 升级完成"

echo "✅ [DIY-P1] 所有第三方包预处理完成"
