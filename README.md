# m-ui 部署

在目标服务器上使用安装脚本部署 m-ui。

## 要求

- Linux
- systemd
- root 用户或 sudo 权限
- 服务器可访问 GitHub Release

## 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mack-a/m-ui-preview/main/install.sh)
```

脚本会：

- 从 `mack-a/m-ui` 最新 Release 下载相应的安装包。
- 安装到 `/etc/mui`
- 写入 `/etc/mui/m-ui.env`
- 创建并启动 `m-ui.service`
- 自动选择可用端口并尝试开放防火墙

安装完成后，终端会输出访问地址。

## 指定版本

```bash
VERSION=v0.1.0 bash <(curl -fsSL https://raw.githubusercontent.com/mack-a/m-ui-preview/main/install.sh)
```

## 管理

再次执行安装脚本会进入管理菜单，可重启、停止、重置或卸载 m-ui。
