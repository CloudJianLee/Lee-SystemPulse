# System Pulse

一款原生 macOS 菜单栏 CPU 与内存监控工具。

## 功能

- 实时显示 CPU 与内存使用率
- CPU 从左向右填充，内存从右向左填充
- 四档负载提示：绿色、橙色、红色、深红色
- 60 次采样历史曲线与详细占用数据
- 支持 1、2、5 秒刷新频率
- 支持开机自动启动
- 不收集数据，不包含遥测

## Requirements

- macOS 14 或更高版本
- Xcode 16 或更高版本
- XcodeGen

## Build

```sh
xcodegen generate
xcodebuild -project SystemPulse.xcodeproj -scheme SystemPulse test
```

状态颜色：

- 低于 80%：充电绿
- 80% 至 90%：警告橙
- 90% 至 95%：警告红
- 95% 至 100%：深红色严重拥塞

## Run

构建后打开：

```text
.build/Build/Products/Debug/System Pulse.app
```

## 发布构建

```sh
./scripts/build-release.sh 1.0.0
```

安装包会生成到 `dist/System-Pulse-1.0.0.dmg`。

> 当前公开构建使用临时签名。若 macOS 阻止首次打开，请右键应用并选择“打开”。

## 许可证

[MIT](LICENSE)
