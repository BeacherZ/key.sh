## 交互式 SSH 安全配置脚本 · 一键加固你的 VPS

密钥管理 · 密码登录开关 · Fail2Ban 防护 · 端口修改

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?logo=linux&logoColor=black)](#)
![GitHub Stars](https://img.shields.io/github/stars/BeacherZ/key.sh?style=flat-square)

</div>

---

## ✨ 功能

- 🔑 **密钥登录管理** — GitHub 拉取 / VPS 生成 / URL 导入 / 查看删除 / 一键开关
- 🔒 **密码登录开关** — 启用或禁用 `PasswordAuthentication`
- 🛡️ **Fail2Ban 防护** — 一键安装 / 参数调整 / 指数递增封禁 / 白名单 / 日志
- 🔧 **SSH 端口修改** — 自动放行防火墙，同步 Fail2Ban 端口
- ⚠️ **防锁死保护** — 危险操作前红色警告 + 二次确认

---

## 🐧 支持的系统

Debian · Ubuntu · RHEL · CentOS · Rocky · AlmaLinux · Fedora · Oracle · Amazon Linux · Alpine · Arch · Manjaro · openSUSE

自动检测包管理器、Init 系统、SSH 日志路径与防火墙。

---

## 🚀 快速开始

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh)
```

> 需要 root 权限或 sudo，首次运行自动安装缺失依赖。

---

## 🖥️ 界面预览

```
============================================================
                     SSH 安全配置工具
============================================================
 系统架构 : Debian 12
 密钥登录 : 已启用 (1 把公钥)
 密码登录 : 已禁用 (PasswordAuthentication no)
 Fail2Ban : 防护中 (已封禁0 IP)
 SSH 端口 : 22
============================================================
 1. 密钥登录管理
 2. 密码登录开关
 3. Fail2Ban防护
 4. SSH 端口修改
 0. 退出脚本
============================================================
```

---


## ⌨️ 命令行模式

无需进入交互菜单，可直接执行单次操作；多个参数可以组合，脚本会按固定顺序执行。

### 常用命令

```bash
./key.sh -g <GitHub用户名>    # 从 GitHub 拉取公钥
./key.sh -u <URL>             # 从自定义 URL 拉取公钥
./key.sh -f <文件>            # 从本地文件导入公钥
./key.sh -p <端口>            # 修改 SSH 端口（自动同步防火墙与 Fail2Ban）
./key.sh -d                   # 禁用密码登录
./key.sh -h                   # 显示帮助
```

### 组合用法

```bash
# 一次性完成：拉取公钥 → 改端口 → 禁用密码登录
./key.sh -g <GitHub用户名> -p 2222 -d

# 覆盖模式：先清空已存公钥，再追加（-o 必须与 -g/-u/-f 配合）
./key.sh -o -g <GitHub用户名>
./key.sh -o -f /path/to/PublicKey.pub
```

### 参数说明

| 参数 | 说明 | 可单独使用 |
|---|---|:---:|
| `-g <用户名>` | 从 GitHub 拉取公钥 | ✅ |
| `-u <URL>` | 从自定义 URL 拉取公钥 | ✅ |
| `-f <文件>` | 从本地文件导入公钥 | ✅ |
| `-p <端口>` | 修改 SSH 端口 | ✅ |
| `-d` | 禁用密码登录 | ✅ |
| `-o` | 覆盖模式，清空已存公钥 | ❌ 需配合 `-g`/`-u`/`-f` |
| `-h` | 显示帮助 | ✅ |



---

## 📖 使用示例

**新 VPS 初始化推荐流程：**

```
1. 运行脚本 → 1. 密钥登录管理 → 选 1/2/3 添加公钥
2. 【重要】新建终端，用密钥登录测试
3. 测试成功后 → 2. 密码登录开关 → 禁用密码登录
4. 3. Fail2Ban防护 → 一键安装
```

**修改端口：**

脚本会自动同步：`sshd_config` 更新 → 防火墙放行 → Fail2Ban 端口同步 → 重启 SSH 服务。

> ⚠️ 记得在云服务商安全组中放行新端口。

---

## ⚠️ 安全提示

- 禁用密码登录前，请**先新建终端验证密钥登录成功**
- 危险操作会弹出红色警告与二次确认，请仔细阅读
- 建议把常用 IP 加入 Fail2Ban 白名单，避免误封自己
- 脚本不收集任何信息，所有操作均为本地执行

---



<div align="center">

如果这个脚本帮到了你，欢迎点一个 ⭐
