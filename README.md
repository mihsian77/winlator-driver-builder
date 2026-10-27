# Winlator Pulse Turnip Driver Builder

自动从 Mesa 上游编译 Turnip 驱动，打包成 Winlator tzst 格式。

## 输出格式

```
turnip-<version>-<variant>-git<hash>.tzst
```

- 标准版（standard）：上游 Mesa 原生，兼容性最好
- Adreno 8XX 版（a8xx）：支持新 GPU（骁龙 8 Elite 等）
- 性能版（perf）：强制最高频率，追求性能

## 自动同步机制

- 每小时检查 Mesa main 分支是否有新提交
- 有变化自动触发编译
- 版本号按 GitHub run number 自动递增

## 使用方式

编译产物自动上传到 [winlator-components](https://github.com/mihsian77/winlator-components) 的 turnip Release。

## 技术栈

- NDK r29
- meson >= 1.4
- Python 幂等补丁系统
