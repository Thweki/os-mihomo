PKG_NAME?=	os-mihomo
VERSION?=	1.2.0
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

# 在测试设备上安装本地构建的包（会执行包钩子）。
install: package
	pkg add "./dist/$(PKG_NAME).pkg"

# 管理员命令行入口，要求已配置受信的软件源。
install-repo:
	pkg install -r "$(REPO_NAME)" "$(PKG_NAME)"

clean:
	rm -rf work/freebsd-pkg dist/repo
