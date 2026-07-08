#!/bin/bash
# 清理重复源
sed -i '/src-git kenzo/d' feeds.conf.default
sed -i '/src-git small/d' feeds.conf.default
sed -i '/src-git istore/d' feeds.conf.default
sed -i '/src-git nas /d' feeds.conf.default
sed -i '/src-git nas_luci/d' feeds.conf.default

# 添加插件源
sed -i '$a src-git kenzo https://github.com/kenzok8/openwrt-packages' feeds.conf.default
sed -i '$a src-git small https://github.com/kenzok8/small' feeds.conf.default
sed -i '$a \\nsrc-git istore https://github.com/linkease/istore;main' feeds.conf.default
sed -i '$a \\nsrc-git nas https://github.com/linkease/nas-packages.git;master' feeds.conf.default
sed -i '$a src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' feeds.conf.default

# 打印源调试，方便看是否写入成功
cat feeds.conf.default

# 必须完整执行更新+安装
./scripts/feeds update -a
./scripts/feeds install -a
