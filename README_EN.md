# Interactive SSH Hardening Script · Harden Your VPS in One Go

<p align="center">English ｜ <a href="README.md">简体中文</a></p>

Key-based login management · password login toggle · Fail2Ban protection · SSH port change

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?logo=linux&logoColor=black)](#)
![GitHub Stars](https://img.shields.io/github/stars/BeacherZ/key.sh?style=flat-square)

---

## ✨ Features

- 🔑 **Key-based login management** — pull from GitHub / generate on the VPS / import from a URL / one-key toggle
- 🔒 **Password login toggle** — enable or disable `PasswordAuthentication`
- 🛡️ **Fail2Ban protection** — one-click install / parameter tuning / exponential ban escalation / allowlist / logs
- 🔧 **SSH port change** — opens the firewall automatically and syncs the Fail2Ban port
- ⚠️ **Lockout protection** — red warnings and double confirmation before anything dangerous

---

## 🐧 Supported systems

Debian · Ubuntu · RHEL · CentOS · Rocky · AlmaLinux · Fedora · Oracle · Amazon Linux · Alpine · Arch · Manjaro · openSUSE

The package manager, init system, SSH log path, and firewall are detected automatically.

---

## 🚀 Quick start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/key.sh/main/key.sh)
```

> Requires root or sudo. Missing dependencies are installed automatically on first run.

---

## 🖥️ UI preview

> The interactive menu is rendered in Chinese.

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

## ⌨️ Command-line mode

Skip the menu and run single operations directly. Multiple flags can be combined; they execute in a fixed order.

### Common commands

```bash
./key.sh -g <github-username>  # pull public keys from GitHub
./key.sh -u <URL>              # pull public keys from a custom URL
./key.sh -f <file>             # import public keys from a local file
./key.sh -p <port>             # change the SSH port (firewall and Fail2Ban synced automatically)
./key.sh -d                    # disable password login
./key.sh -h                    # show help
```

### Combined usage

```bash
# All at once: pull keys → change port → disable password login
./key.sh -g <github-username> -p 2222 -d

# Overwrite mode: clear stored keys first, then append (-o must be combined with -g/-u/-f)
./key.sh -o -g <github-username>
./key.sh -o -f /path/to/PublicKey.pub
```

### Flags

| Flag | Description | Standalone |
|---|---|:---:|
| `-g <username>` | Pull public keys from GitHub | ✅ |
| `-u <URL>` | Pull public keys from a custom URL | ✅ |
| `-f <file>` | Import public keys from a local file | ✅ |
| `-p <port>` | Change the SSH port | ✅ |
| `-d` | Disable password login | ✅ |
| `-o` | Overwrite mode, clears stored keys | ❌ needs `-g`/`-u`/`-f` |
| `-h` | Show help | ✅ |

---

## 📖 Usage examples

**Recommended flow for a fresh VPS:**

```
1. Run the script → 1. Key-based login management → pick 1/2/3 to add a public key
2. [Important] Open a NEW terminal and verify you can log in with the key
3. After a successful test → 2. Password login toggle → disable password login
4. 3. Fail2Ban protection → one-click install
```

**Changing the port:**

The script syncs everything for you: update `sshd_config` → open the firewall → sync the Fail2Ban port → restart SSH.

> ⚠️ Remember to open the new port in your cloud provider's security group.

---

## ⚠️ Security notes

- Before disabling password login, **open a new terminal first and confirm key login works**
- Dangerous operations raise a red warning and a second confirmation — read them carefully
- Add your usual IPs to the Fail2Ban allowlist so you never lock yourself out
- The script collects nothing; every operation runs locally

---

<div align="center">

If this script helped you, a ⭐ is appreciated
