# Linux SSH 密钥与安全一键配置工具 (`key.sh`)

一个轻量、高效且安全的 Linux SSH 运维脚本。支持一键导入/生成 SSH 密钥、更改服务端口、禁用密码登录以及公钥精准可视化管理。

适用于云服务器初始化、VPS 秘钥管理及安全加固。

---

## ✨ 核心特性

- 🔑 **灵活的密钥管理**
  - **GitHub 一键拉取**：直接输入 GitHub 用户名即可批量导入公钥。
  - **干净生成 ED25519**：本地快速生成新密钥对，自动剔除主机名/邮箱等尾部标识（无痕安全）。
  - **多源导入**：支持自定义 URL 拉取与本地文件导入。
  - **可视化表格管理**：直观展示已存公钥的添加时间、类型与备注来源，支持按序号单条精准删除或一键清空。

- 🛡️ **安全防护与加固**
  - **一键开关密码登录**：轻松开启或彻底禁用密码登录（同步禁用 `ChallengeResponseAuthentication` 和 `KbdInteractiveAuthentication`）。
  - **修改 SSH 端口**：支持 1024-65535 自定义端口，并**自动放行 UFW / Firewalld / SELinux** 相应规则。
  - **安全防锁死保护**：
    - 在应用任何配置前强制进行 `sshd -t` 语法检查。
    - 智能检测当前 SSH 远程会话并弹出预警提示。
    - 自动处理 Debian/Ubuntu 系统下 `systemd ssh.socket` 导致的服务重启失效问题。

- ⚡ **全系统兼容与 CLI 支持**
  - 自动检测并安装缺失依赖（`curl`, `ssh-keygen`, `gawk`）。
  - 完美兼容主流 Linux 发行版（Debian, Ubuntu, CentOS, RHEL, Rocky Linux, AlmaLinux, Alpine Linux 等）。
  - 提供 CLI 命令行参数，方便集成至自动化脚本或 Cloud-init。

---

## 🚀 快速开始

### 交互式菜单运行（推荐）

直接在终端执行以下命令：

```bash
curl -sSL [https://raw.githubusercontent.com/your-username/repo-name/main/key.sh](https://raw.githubusercontent.com/your-username/repo-name/main/key.sh) | bash
