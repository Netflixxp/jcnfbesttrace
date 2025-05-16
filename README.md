# jcNextTrace - 基于 NextTrace 的网络路由追踪脚本

`jcNextTrace` 是一个 Bash 脚本，它封装了强大的路由追踪工具 [NextTrace](https://github.com/nxtrace/NTrace-core)，旨在提供一个用户友好的界面，用于测试到不同网络运营商和自定义 IP 地址的网络路径和延迟。

## 功能特性

- **多种测试模式**：
    - **运营商选择测试**：从预设的 ISP 节点列表中选择特定运营商的节点进行测试。
    - **四网快速测试**：自动对国内主要的 ISP（电信、联通、移动、教育网）的代表性节点进行快速路由追踪。
    - **手动 IP 测试**：输入任意 IP 地址进行路由追踪。
- **外部化节点配置**：
    - 测试节点（IP 地址和名称）通过外部 `isp_nodes.conf` 文件进行管理，方便用户自定义和更新。
    - 脚本在运行时会自动从指定的 URL 下载最新的 `isp_nodes.conf` 文件。
- **自动安装和更新 NextTrace**：
    - 脚本会自动检测系统中是否安装了 `NextTrace`。
    - 如果未安装，会尝试使用官方安装脚本（默认使用中国镜像源）进行安装。
    - 提供菜单选项方便用户更新 `NextTrace` 到最新版本。
- **依赖自动处理**：
    - 自动检测并安装必要的依赖项（如 `wget`, `curl`）。
- **用户友好的交互界面**：
    - 彩色输出，清晰的菜单选项和提示信息。
    - 测试结果会同时输出到屏幕和日志文件 (`/home/tstrace/jcnxtrace.log`)。
- **跨平台兼容性**：
    - 设计为在主流 Linux 发行版上运行 (Debian/Ubuntu, CentOS/RHEL/Fedora 等)。

## 环境要求

- **操作系统**：Linux (已在 Debian, Ubuntu, CentOS 上测试)
- **必要工具**：
    - `bash`
    - `wget` (用于下载配置文件)
    - `curl` (用于安装/更新 NextTrace)
    - `NextTrace` (脚本会自动尝试安装)
- **权限**：
    - 首次运行安装 NextTrace 或更新 NextTrace 时，可能需要 `root` 权限。脚本会给出相应提示。
    - 日常运行测试通常不需要 `root` 权限（除非 NextTrace 本身有特定模式需要）。

## 安装与使用

### 1. 下载脚本

你可以通过以下命令下载脚本（请将 `<YOUR_SCRIPT_RAW_LINK>` 替换为你脚本在 GitHub 上的实际 Raw 链接）：

```bash
wget -O jcNextTrace.sh https://raw.githubusercontent.com/Netflixxp/jcnfbesttrace/main/jcNextTrace.sh && chmod +x jcNextTrace.sh && ./jcNextTrace.sh
```
### 2. 再次运行
```bash
./jcNextTrace.sh
```
