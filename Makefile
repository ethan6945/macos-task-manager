APP := build/Task Manager.app
# 图标方案：spikes / spikes-blue / chip / bars / gauge / pulse
ICON_STYLE ?= spikes

.PHONY: all build debug run stop clean icon icon-previews dmg

all: build

## 构建 release 版并组装 .app
build:
	@CONFIG=release bash Scripts/bundle.sh

## 构建 debug 版（编译快，用于开发）
debug:
	@CONFIG=debug bash Scripts/bundle.sh

## 构建并启动
run: build
	@pkill -x "Task Manager" 2>/dev/null || true
	@open "$(APP)"

## 关闭正在运行的实例
stop:
	@pkill -x "Task Manager" 2>/dev/null || true

## 重新生成 App 图标（ICON_STYLE=spikes|spikes-blue|chip|bars|gauge|pulse）
icon:
	@swiftc -O -parse-as-library Scripts/MakeIcon.swift -o .build/makeicon
	@mkdir -p Resources && .build/makeicon "$(PWD)/Resources" $(ICON_STYLE)
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "==> Resources/AppIcon.icns（$(ICON_STYLE)）"

## 出 4 个方案的预览图，方便挑
icon-previews:
	@swiftc -O -parse-as-library Scripts/MakeIcon.swift -o .build/makeicon
	@mkdir -p build/icon-previews && .build/makeicon "$(PWD)/build/icon-previews" --previews

## 打一个可分发的 DMG
dmg: build
	@bash Scripts/make-dmg.sh

clean:
	@swift package clean
	@rm -rf build .build
