PKG_NAME?=	os-mihomo
VERSION?=	1.1.0
# OPNsense 插件仓库按 ABI 分目录，默认构建本机 ABI（FreeBSD:15:amd64 之类）。
# 只做单文件分发（pkg add -f）时可改为 ABI=universal。
ABI?=		native
# 写进包清单的仓库名（插件页面显示为「仓库」）。
REPO_NAME?=	os-mihomo

.PHONY: package repo install install-repo clean

package:
	ABI="$(ABI)" PKG_NAME="$(PKG_NAME)" VERSION="$(VERSION)" REPO_NAME="$(REPO_NAME)" ./build.sh

# 生成标准 OPNsense 插件仓库目录：dist/repo/<ABI>/
# 把它放到任意静态站点（或本机目录）后，在 /usr/local/etc/pkg/repos/<name>.conf
# 里指向它，即可用「系统 > 固件 > 插件」安装/升级/卸载本插件。
repo: package
	PKG_NAME="$(PKG_NAME)" VERSION="$(VERSION)" REPO_NAME="$(REPO_NAME)" sh scripts/make_repo.sh

# 单文件安装（会执行包内 +POST_INSTALL）
install: package
	pkg add -f "dist/$(PKG_NAME).pkg"

# 经由本地仓库安装：走 pkg install，等价于插件管理器的安装路径
install-repo: repo
	pkg install -y "$(PKG_NAME)"

clean:
	rm -rf work/freebsd-pkg dist/repo
