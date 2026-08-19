#!/bin/bash
# diy-part1.sh（Before Update feeds）
# 作用：删除官方 luci 源里的 JS 版 dockerman，避免和 lisaac 的 Lua 版冲突

echo "--- 删除官方 luci 源中的 JS 版 dockerman ---"

# 官方 luci 里 dockerman 的路径（ImmortalWrt/OpenWrt 主线位置）
RM_PATH="feeds/luci/applications/luci-app-dockerman"

if [ -d "$RM_PATH" ]; then
    rm -rf "$RM_PATH"
    echo "✅ 已删除官方 JS 版 dockerman"
else
    echo "⚠️ 未找到 $RM_PATH，可能路径已变，请检查"
fi
