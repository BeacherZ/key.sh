# Linux SSH 密钥与安全一键配置工具 (`key.sh`)

一个轻量、高效且安全的 Linux SSH 运维脚本。支持一键导入/生成 SSH 密钥、更改服务端口、禁用密码登录以及公钥精准可视化管理。

适用于云服务器初始化、VPS 密钥管理及安全加固。

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

## 🚀 一键执行命令

在终端复制并粘贴以下代码，即可自动下载并启动交互菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh)

```

---

## 🛠️ CLI 无人值守参数

支持在自动化脚本中通过命令行参数快速配置：

| 参数 | 格式 / 示例 | 说明 |
| --- | --- | --- |
| `-g` | `-g <GitHub用户名>` | 从 GitHub 拉取公钥并启用密钥登录 |
| `-u` | `-u <URL>` | 从指定自定义 URL 拉取公钥并写入 |
| `-f` | `-f <文件路径>` | 从本地公钥文件导入 |
| `-p` | `-p <端口号>` | 修改 SSH 服务端口（如 `-p 2222`） |
| `-d` | `-d` | 禁用 SSH 密码登录（纯密钥模式） |
| `-o` | `-o` | **覆盖模式**（结合 `-g/-u/-f` 使用，导入前先清空旧公钥） |

### CLI 调用示例

```bash
# 示例 1: 从 GitHub 拉取公钥并禁用密码登录
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh) -g "你的GitHub用户名" -d

# 示例 2: 清空原有公钥并覆盖导入，同时修改 SSH 端口为 22222
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh) -o -g "你的GitHub用户名" -p 22222

```

---

## 🖥️ 菜单预览

```plain
============================================================
                     SSH 密钥安全配置工具
============================================================
 系统架构 : Debian GNU/Linux 12 (bookworm)
 SSH 端口 : 22
 密码登录 : 已开启 (推荐配置密钥后禁用)
 密钥登录 : 已启用 (PubkeyAuthentication yes)
 已存公钥 : 1 条记录 (/root/.ssh/authorized_keys)
============================================================
 1. 配置/添加 SSH 密钥
 2. 开启/禁用 密码登录
 3. 修改 SSH 端口
 4. 公钥管理
 0. 退出脚本
============================================================

```

---

## ⚠️ 注意事项

1. **测试连接再关闭窗口**：修改 SSH 端口或禁用密码登录后，**请勿立即关闭当前 SSH 终端**。请新建一个终端窗口测试能否顺利连接新端口/密钥登录。
2. **云服务器安全组/防火墙**：脚本会自动放行本机防火墙（UFW/Firewalld），但如果使用的是阿里云、腾讯云、AWS 等云厂商 VPS，请务必前往**厂商后台的安全组/防火墙**中放行相应的新端口。

---

## 📄 开源协议

本项目采用 [MIT License](https://www.google.com/search?q=LICENSE) 协议开源。



