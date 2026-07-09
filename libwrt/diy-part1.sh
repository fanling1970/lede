
#!/bin/bash
# 提前删除官方自带openclash，避免feeds优先加载原版冲突
rm -rf feeds/luci/applications/luci-app-openclash
# 提前删除官方passwall，避免优先级冲突
rm -rf feeds/luci/applications/luci-app-passwall

# 清理旧重复软件源行
sed -i '/src-git kenzo/d' feeds.conf.default
sed -i '/src-git small/d' feeds.conf.default
sed -i '/src-git istore/d' feeds.conf.default
sed -i '/src-git nas /d' feeds.conf.default
sed -i '/src-git nas_luci/d' feeds.conf.default

# 追加各类插件源
sed -i '$a src-git kenzo https://github.com/kenzok8/openwrt-packages' feeds.conf.default
sed -i '$a src-git small https://github.com/kenzok8/small' feeds.conf.default
sed -i '$a \\nsrc-git istore https://github.com/linkease/istore;main' feeds.conf.default
sed -i '$a \\nsrc-git nas https://github.com/linkease/nas-packages.git;master' feeds.conf.default
sed -i '$a src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' feeds.conf.default

# 打印源调试，查看是否写入成功
cat feeds.conf.default

# 清理旧残缺仓库缓存，强制完整拉取
rm -rf feeds/small feeds/kenzo

# 更新并安装全部feeds
./scripts/feeds update -a
./scripts/feeds install -a
