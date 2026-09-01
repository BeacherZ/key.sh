# 🔐 SSH Key & Security Installer

一键搞定 Linux 服务器的 SSH 密钥配置、端口修改和密码登录禁用，兼容主流 Linux 发行版。



---

## 📦 功能特性

- **一键导入 SSH 公钥**
  - 从 GitHub 拉取（输入用户名即可）
  - 从自定义 URL 导入
  - 从本地文件导入
  - 支持覆盖模式（`-o`）

- **在服务器上安全生成 ED25519 密钥对**
  - 无痕生成（`-C ""` 清除后缀标识）
  - 自动将公钥写入 `authorized_keys`
  - 生成的密钥对直接显示在终端，供本地保存（或通过 SFTP 下载）

- **交互式公钥可视化管理**
  - 列表展示所有已存公钥（含添加时间、密钥类型、来源备注）
  - 支持按序号删除单条公钥
  - 支持一键清空所有公钥

- **安全加固**
  - 一键禁用密码登录（同时关闭 `ChallengeResponseAuthentication` 和 `KbdInteractiveAuthentication`）
  - 修改 SSH 端口，并自动放行 `UFW` / `Firewalld` / `SELinux`
  - 修改前自动执行 `sshd -t` 语法检查，防止配置错误导致断连
  - 智能检测远程会话，操作前给出安全提示

- **全平台兼容**
  - 支持 `systemd`（Debian/Ubuntu/CentOS/RHEL）和 `OpenRC`（Alpine）
  - 自动安装依赖（`curl`, `ssh-keygen`, `gawk`）

- **命令行无人值守模式**
  - 支持通过参数快速完成配置，便于集成到 `cloud-init` 或自动化脚本

---

## 🚀 快速开始

在终端中执行以下命令，即可下载并启动交互式菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh)
```

---

## 🖥️ 交互式菜单使用

运行脚本后会显示当前 SSH 状态面板，并提供以下功能选项：

```
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

### 选项说明

| 选项 | 功能 |
|------|------|
| `1` | 添加 SSH 密钥（支持 GitHub / 本地生成 / 自定义 URL） |
| `2` | 切换密码登录状态（启用或禁用） |
| `3` | 修改 SSH 服务端口（自动放行防火墙） |
| `4` | 管理已存公钥（查看、删除单条、清空全部） |
| `0` | 退出脚本 |

---

## ⚙️ CLI 命令行参数（无人值守）

适用于自动化脚本或 `cloud-init` 初始化。所有参数可组合使用。

| 参数 | 格式 | 说明 |
|------|------|------|
| `-g` | `-g <GitHub用户名>` | 从 GitHub 拉取该用户的公钥并启用密钥登录 |
| `-u` | `-u <URL>` | 从指定 URL 下载公钥并导入 |
| `-f` | `-f <文件路径>` | 从本地文件导入公钥 |
| `-p` | `-p <端口号>` | 修改 SSH 端口为指定值（需在 1024-65535 之间） |
| `-d` | `-d` | 禁用密码登录（纯密钥模式） |
| `-o` | `-o` | **覆盖模式**（与 `-g/-u/-f` 配合使用，导入前清空已有公钥） |

### CLI 使用示例

```bash
# 从 GitHub 拉取公钥并禁用密码登录
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh) -g "your_username" -d

# 清空原有公钥，从 GitHub 重新导入，并修改端口为 22222
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh) -o -g "your_username" -p 22222

# 从自定义 URL 导入公钥（覆盖模式）
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh) -o -u "https://example.com/mykey.pub"

# 仅修改 SSH 端口为 2222
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh) -p 2222
```

---

## 🔒 安全提示

- **始终先测试再关闭会话**  
  修改端口或禁用密码登录后，**请勿立即关闭当前 SSH 窗口**。应新建一个终端会话，使用新端口/密钥尝试登录，确认成功后再退出旧会话，避免被锁在服务器外。

- **云服务商安全组**  
  脚本会自动放行系统防火墙（UFW/Firewalld），但如果您使用阿里云、腾讯云、AWS 等云厂商，还需在 **厂商控制台的安全组/防火墙** 中放行您修改后的端口。

- **私钥保护**  
  使用脚本生成的私钥（`PrivateKey.pem`）请务必妥善保存，切勿泄露。建议下载到本地后删除服务器上的临时副本。

---

## 🖥️ 兼容性

| 发行版 | 支持情况 |
|--------|----------|
| Debian / Ubuntu | ✅ 完美支持 |
| CentOS / RHEL / Rocky / AlmaLinux | ✅ 完美支持 |
| Alpine Linux | ✅ 完美支持（OpenRC） |
| 其他 systemd 发行版 | ✅ 基本支持 |

脚本会自动检测系统并适配相应的服务管理命令。

---

## 📥 依赖与安装

脚本会**自动安装**所需依赖（如果缺失）：
- `curl`：用于网络请求
- `openssh-client` / `openssh-clients`：提供 `ssh-keygen`
- `gawk`：用于文本处理

您也可以手动安装这些工具，但脚本已内置自动安装逻辑。

---

## 🤝 贡献与反馈

欢迎提交 Issue 或 Pull Request。如果您有任何建议或发现 Bug，请通过 GitHub 仓库反馈。
