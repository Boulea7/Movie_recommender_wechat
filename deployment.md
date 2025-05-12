# 电影推荐系统部署指南

> 作者：电影推荐系统团队  
> 版本：2.1.0  
> 更新日期：2025-05-15

本文档提供了在纯净的Ubuntu系统上部署电影推荐系统的完整指南，包括自动化和手动部署方法、常见问题排查和系统维护。

## 目录

- [快速部署](#快速部署)
- [系统要求](#系统要求)
- [一键自动部署](#一键自动部署)
- [详细部署步骤](#详细部署步骤)
- [端口配置](#端口配置)
- [微信公众号配置](#微信公众号配置)
- [常见问题排查](#常见问题排查)
- [系统维护](#系统维护)
- [高级配置](#高级配置)
- [变更日志](#变更日志)

## 快速部署

以下是在纯净系统上快速部署电影推荐系统的步骤：

```bash
# 1. 更新系统并安装Git
sudo apt update
sudo apt install -y git

# 2. 克隆项目代码
git clone https://github.com/Boulea7/Movie_recommender_wechat /tmp/recommender

# 3. 执行部署脚本
cd /tmp/recommender
sudo chmod +x scripts/*.sh
sudo bash scripts/unified_deploy.sh

# 4. 验证部署
curl http://localhost/
sudo systemctl status movie-recommender.service
```

如果部署过程中出现问题，请参考[常见问题排查](#常见问题排查)部分。

## 系统要求

- **操作系统**：Ubuntu 20.04 LTS或更高版本
- **硬件**：
  - CPU：2核或更高
  - 内存：2GB或更高
  - 磁盘：20GB可用空间
- **软件**：
  - Python 3.8或更高版本
  - MySQL 5.7或更高版本
  - 开放80端口（微信公众号需要）

## 一键自动部署

我们提供了全新的一键自动部署脚本`unified_deploy.sh`，它可以解决部署过程中的常见问题，包括：

1. 端口问题：自动处理80/8080端口配置
2. 权限问题：自动设置绑定低端口特权
3. Python环境问题：使用虚拟环境解决依赖安装问题
4. 配置解析问题：确保ConfigParser包含必要的方法
5. 数据库问题：自动配置和启动MySQL服务

### 使用一键部署脚本

```bash
# 下载脚本
wget https://raw.githubusercontent.com/your_username/recommender/master/scripts/unified_deploy.sh

# 赋予执行权限
chmod +x unified_deploy.sh

# 执行部署脚本
sudo ./unified_deploy.sh
```

### 部署脚本参数

脚本支持以下环境变量来自定义部署：

- `INSTALL_DIR`：安装目录（默认：/opt/recommender）
- `PORT`：Web服务器端口（默认：80）
- `USE_NGINX`：是否使用Nginx反向代理（默认：false）

```bash
# 示例：自定义安装目录和端口
sudo INSTALL_DIR=/usr/local/recommender PORT=8080 ./unified_deploy.sh

# 示例：强制使用Nginx反向代理
sudo USE_NGINX=true ./unified_deploy.sh
```

### 部署过程

1. 系统依赖检查和安装
2. MySQL服务配置
3. 项目文件部署
4. Python虚拟环境配置
5. 配置解析器检查和修复
6. 数据库初始化
7. 服务端口配置
8. 端口绑定权限设置
9. 系统服务创建与启动
10. Nginx配置（如需要）
11. 防火墙设置

部署完成后，脚本会显示摘要信息和常用管理命令。

## 详细部署步骤

### 1. 系统准备

首先更新系统并安装必要的软件包：

```bash
# 更新系统软件包
sudo apt update
sudo apt upgrade -y

# 安装必要的软件包
sudo apt install -y python3 python3-pip python3-venv mysql-server git curl wget net-tools libmysqlclient-dev
```

### 2. 配置MySQL

安装并配置MySQL数据库：

```bash
# 确保MySQL已启动
sudo systemctl start mysql
sudo systemctl enable mysql

# 设置MySQL root密码（如果尚未设置）
sudo mysql_secure_installation

# 登录MySQL创建必要的数据库和用户
sudo mysql -u root -p
```

在MySQL命令行中执行：

```sql
CREATE DATABASE douban DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'douban_user'@'localhost' IDENTIFIED BY 'MySQL_20050816Zln@233';
GRANT ALL PRIVILEGES ON douban.* TO 'douban_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 3. 获取项目代码

```bash
# 创建项目目录
sudo mkdir -p /opt/recommender

# 克隆项目代码
git clone https://github.com/your_username/recommender.git /tmp/recommender

# 复制项目文件到目标目录
sudo cp -r /tmp/recommender/* /opt/recommender/
```

### 4. 配置项目

#### 4.1 创建Python虚拟环境

由于Ubuntu和某些Linux发行版使用外部管理的Python环境（PEP 668），我们需要使用虚拟环境来安装项目依赖：

```bash
# 创建虚拟环境
cd /opt/recommender
sudo python3 -m venv venv

# 使用虚拟环境安装依赖
sudo venv/bin/pip install --upgrade pip
sudo venv/bin/pip install -r requirements.txt
```

#### 4.2 配置数据库连接

检查并编辑数据库配置文件：

```bash
sudo nano /opt/recommender/config/database.conf
```

确保配置文件内容如下：

```ini
[database]
host = localhost
port = 3306
user = douban_user
password = MySQL_20050816Zln@233
db = douban
charset = utf8mb4
pool_size = 5
timeout = 60
reconnect_attempts = 3

[service]
port = 80
token = HelloMovieRecommender
encoding_key = X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a
debug = false
log_level = INFO

[recommender]
similarity_threshold = 0.5
min_ratings = 3
max_recommendations = 10
```

### 5. 初始化数据库

执行数据库初始化脚本：

```bash
# 给脚本添加执行权限
sudo chmod +x /opt/recommender/scripts/*.sh

# 执行数据库初始化脚本
cd /opt/recommender
sudo bash scripts/init_database.sh
```

如果需要指定MySQL root密码，可以使用：

```bash
sudo DB_ROOT_PASSWORD=your_mysql_root_password bash scripts/init_database.sh
```

### 6. 创建系统服务

创建systemd服务文件，使用虚拟环境中的Python解释器：

```bash
sudo bash -c 'cat > /etc/systemd/system/movie-recommender.service << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/recommender
ExecStart=/opt/recommender/venv/bin/python /opt/recommender/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender
# 允许绑定特权端口(80)
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF'
```

### 7. 启动服务

```bash
# 重载systemd配置
sudo systemctl daemon-reload

# 启用并启动服务
sudo systemctl enable movie-recommender.service
sudo systemctl start movie-recommender.service

# 检查服务状态
sudo systemctl status movie-recommender.service
```

### 8. 验证部署

使用curl测试服务是否正常运行：

```bash
curl http://localhost/
```

检查端口监听状态：

```bash
sudo netstat -tuln | grep 80
```

## 端口配置

微信公众号要求使用80端口。有两种方式确保服务能够使用80端口：

### 方案1：直接使用80端口（默认方案）

此方案要求服务以root权限运行或拥有`CAP_NET_BIND_SERVICE`权限：

```bash
# 使用我们提供的更新服务脚本
sudo bash /opt/recommender/scripts/update_service.sh
```

### 方案2：使用Nginx反向代理

如果您希望服务以非特权用户运行，或80端口被其他服务占用，可使用Nginx作为反向代理：

```bash
# 使用我们提供的Nginx配置脚本
sudo bash /opt/recommender/scripts/setup_nginx.sh
```

此脚本会：
1. 安装Nginx
2. 配置服务使用8080端口
3. 设置Nginx反向代理将80端口流量转发到8080端口
4. 重启所有相关服务

## 微信公众号配置

在完成系统部署后，您需要配置微信公众号：

1. 登录微信公众平台
2. 进入开发 -> 基本配置
3. 设置服务器地址(URL): `http://您服务器的IP地址/`
4. 设置Token: 与`/opt/recommender/config/database.conf`中的`token`值保持一致
5. 提交配置并等待验证

更多微信公众号配置详情，请参考[微信公众平台开发文档](https://developers.weixin.qq.com/doc/offiaccount/Getting_Started/Overview.html)。

### 微信公众号调试工具

系统提供了微信调试工具，可以验证配置是否正确：

```bash
# 使用虚拟环境Python运行调试工具
cd /opt/recommender
venv/bin/python scripts/wechat_debug.py --validate
```

此工具将检查：
- 服务器连接性
- Token配置
- 消息处理功能
- 微信API调用

## 常见问题排查

### 自动诊断工具

系统提供了自动诊断和修复工具：

```bash
# 诊断系统问题
sudo bash /opt/recommender/scripts/troubleshoot.sh

# 诊断并提示修复
sudo bash /opt/recommender/scripts/troubleshoot.sh -f

# 自动修复所有问题
sudo bash /opt/recommender/scripts/troubleshoot.sh -fy
```

### 常见错误及解决方法

#### 1. ModuleNotFoundError: No module named 'web'

**问题**：缺少web.py模块。
**解决方法**：
```bash
cd /opt/recommender
sudo venv/bin/pip install web.py
```

#### 2. externally-managed-environment 错误

**问题**：Ubuntu和某些Linux发行版使用外部管理的Python环境（PEP 668），禁止直接使用pip安装包。
**解决方法**：使用Python虚拟环境：
```bash
# 确保安装了python3-venv
sudo apt install -y python3-venv

# 创建虚拟环境
cd /opt/recommender
sudo python3 -m venv venv

# 使用虚拟环境安装依赖
sudo venv/bin/pip install -r requirements.txt

# 更新服务配置使用虚拟环境
sudo sed -i 's|ExecStart=/usr/bin/python3|ExecStart=/opt/recommender/venv/bin/python|' /etc/systemd/system/movie-recommender.service
sudo systemctl daemon-reload
sudo systemctl restart movie-recommender.service
```

#### 3. 数据库连接错误

**问题**：无法连接到MySQL数据库。
**解决方法**：
```bash
# 检查MySQL服务状态
sudo systemctl status mysql

# 如果服务未运行，启动服务
sudo systemctl start mysql

# 验证数据库连接信息
cd /opt/recommender
grep -A8 '\[database\]' config/database.conf

# 手动测试连接
mysql -u douban_user -p"MySQL_20050816Zln@233" -h localhost -e "USE douban; SELECT 1;"

# 重新初始化数据库
sudo bash scripts/init_database.sh
```

#### 4. 80端口占用问题

**问题**：80端口被其他服务占用。
**解决方法**：
```bash
# 查看占用80端口的服务
sudo netstat -tuln | grep ":80 "
sudo lsof -i :80

# 方案1：停止占用端口的服务
sudo systemctl stop nginx  # 假设是nginx占用

# 方案2：使用Nginx反向代理
sudo bash /opt/recommender/scripts/setup_nginx.sh
```

#### 5. 服务启动失败

**问题**：systemd服务启动失败。
**解决方法**：
```bash
# 检查服务状态和日志
sudo systemctl status movie-recommender.service
sudo journalctl -u movie-recommender.service -n 50

# 手动启动检查错误
cd /opt/recommender
sudo venv/bin/python web_server/main.py

# 检查文件权限
sudo chmod +x /opt/recommender/web_server/main.py
sudo chown -R root:root /opt/recommender
```

#### 6. ConfigParser类问题

**问题**：缺少get_section方法或其他配置解析问题。
**解决方法**：
```bash
# 运行配置修复脚本
cd /opt/recommender
sudo bash scripts/fix_config_parser.sh

# 或者使用统一部署脚本重新部署
sudo bash scripts/unified_deploy.sh
```

#### 7. 端口绑定权限问题

**问题**：当配置80端口时出现`Failed to set capabilities on file... (Invalid argument)`错误。
**解决方法**：
```bash
# 方法1：找到Python解释器真实路径并设置权限
PYTHON_PATH=$(readlink -f /opt/recommender/venv/bin/python3)
sudo setcap 'cap_net_bind_service=+ep' $PYTHON_PATH

# 方法2：使用authbind
sudo apt-get install -y authbind
sudo touch /etc/authbind/byport/80
sudo chmod 500 /etc/authbind/byport/80
sudo chown root /etc/authbind/byport/80

# 修改服务文件
sudo nano /etc/systemd/system/movie-recommender.service
# 将ExecStart行修改为:
# ExecStart=/usr/bin/authbind --deep /opt/recommender/venv/bin/python3 /opt/recommender/web_server/main.py

# 重载并重启服务
sudo systemctl daemon-reload
sudo systemctl restart movie-recommender.service
```

#### 8. Python脚本缩进问题

**问题**：Python脚本（如`create_target_table.py`或`main.py`）出现缩进错误，如`TabError: inconsistent use of tabs and spaces in indentation`。
**解决方法**：
```bash
# 下载修复脚本
wget -O /tmp/fix_indentation.sh https://raw.githubusercontent.com/your_username/recommender/master/scripts/fix_indentation.sh

# 或手动创建修复脚本
cat > /tmp/fix_indentation.sh << 'EOF'
#!/bin/bash
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="$INSTALL_DIR/backups"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')

# 备份原始文件
mkdir -p "$BACKUP_DIR"
cp "$INSTALL_DIR/web_server/main.py" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"
cp "$INSTALL_DIR/data_spider/create_target_table.py" "$BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"

# 修复缩进 - 将所有制表符转换为空格
sed -i 's/\t/    /g' "$INSTALL_DIR/web_server/main.py"
sed -i 's/\t/    /g' "$INSTALL_DIR/data_spider/create_target_table.py"

# 重启服务
systemctl restart movie-recommender.service
EOF

# 执行修复脚本
chmod +x /tmp/fix_indentation.sh
sudo bash /tmp/fix_indentation.sh
```

如果自动修复脚本不能解决问题，您也可以从GitHub下载修复好的脚本版本替换原有文件。

**特定问题**：在`data_spider/create_target_table.py`文件中，可能会遇到"expected 'except' or 'finally' block"错误，这表明try语句块缺少对应的except或finally子句。
**解决方法**：
```bash
# 使用我们提供的脚本修复try-except-finally结构问题
sudo bash /opt/recommender/scripts/fix_create_target_table.sh

# 或手动修复代码
sudo nano /opt/recommender/data_spider/create_target_table.py
# 确保每个try块都有对应的except或finally块
```

**web_server/main.py缩进问题**：在`web_server/main.py`中可能存在更复杂的缩进问题，特别是在`update_user_info`方法中。
**解决方法**：
```bash
# 使用我们提供的脚本修复
sudo bash /opt/recommender/scripts/fix_main_py.sh

# 或手动修复缩进问题
sudo nano /opt/recommender/web_server/main.py
# 确保方法中的try-except块正确缩进
```

#### 9. 内存不足问题

**问题**：系统或MySQL内存使用过高，导致服务不稳定。
**解决方法**：
```bash
# 检查内存使用情况
free -h

# 调整MySQL内存使用
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf

# 添加或修改以下配置
# innodb_buffer_pool_size = 256M  # 减少缓冲池大小
# max_connections = 50  # 减少最大连接数

# 重启MySQL
sudo systemctl restart mysql
```

## 系统维护

### 备份与恢复

#### 数据库备份

```bash
# 创建备份目录
sudo mkdir -p /opt/recommender_backups

# 备份数据库
sudo mysqldump -u root -p douban > /opt/recommender_backups/douban_$(date +%Y%m%d).sql

# 定期自动备份（每天凌晨3点）
echo "0 3 * * * root mysqldump -u root -p'your_password' douban > /opt/recommender_backups/douban_\$(date +\%Y\%m\%d).sql" | sudo tee /etc/cron.d/backup_recommender
```

#### 数据库恢复

```bash
# 从备份恢复
sudo mysql -u root -p douban < /opt/recommender_backups/douban_YYYYMMDD.sql
```

#### 自动备份配置

最新的`unified_deploy.sh`脚本会自动配置以下备份任务：

1. 数据库每日备份（凌晨3点）
2. 配置文件每周备份（周日凌晨4点）
3. 系统日志每月归档（每月1日凌晨5点）

备份保留策略：
- 数据库备份保留30天
- 配置备份保留90天
- 日志归档保留365天

### 日志管理

```bash
# 查看服务日志
sudo journalctl -u movie-recommender.service -f

# 查看应用日志
sudo tail -f /opt/recommender/logs/web_server.log

# 查看错误日志
sudo tail -f /opt/recommender/logs/error.log

# 查看访问日志
sudo tail -f /opt/recommender/logs/access.log

# 日志轮转
sudo nano /etc/logrotate.d/movie-recommender
```

配置日志轮转：

```
/opt/recommender/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 root root
    postrotate
        systemctl reload movie-recommender.service >/dev/null 2>&1 || true
    endscript
}
```

### 系统健康检查

最新版本包含自动健康检查功能：

```bash
# 手动运行健康检查
sudo bash /opt/recommender/scripts/health_check.sh

# 健康检查报告
sudo bash /opt/recommender/scripts/health_check.sh --report
```

健康检查会监控以下指标：
- 系统资源使用率（CPU、内存、磁盘）
- 服务状态和响应时间
- 数据库连接和性能
- 日志错误模式
- 备份状态

### 系统更新

```bash
# 停止服务
sudo systemctl stop movie-recommender.service

# 备份当前版本
sudo cp -r /opt/recommender /opt/recommender_backup_$(date +%Y%m%d)

# 更新代码
cd /opt/recommender
sudo git pull

# 更新依赖
sudo venv/bin/pip install -r requirements.txt

# 启动服务
sudo systemctl start movie-recommender.service
```

## 高级配置

### 自定义端口

如果需要更改默认端口，请编辑配置文件：

```bash
sudo nano /opt/recommender/config/database.conf
```

修改`[service]`部分：

```ini
[service]
port = 8080  # 使用自定义端口
```

然后重启服务：

```bash
sudo systemctl restart movie-recommender.service
```

如果更改为非特权端口（>1024），可以移除特权端口绑定权限并使用普通用户运行服务。

### 多实例部署

如果需要部署多个实例（如测试环境和生产环境），可以：

1. 使用不同的安装目录：

```bash
sudo INSTALL_DIR=/opt/recommender_test bash scripts/unified_deploy.sh
```

2. 创建不同的服务名称：

```bash
sudo cp /etc/systemd/system/movie-recommender.service /etc/systemd/system/movie-recommender-test.service
sudo sed -i 's|/opt/recommender|/opt/recommender_test|g' /etc/systemd/system/movie-recommender-test.service
```

3. 配置不同的端口。

### 性能优化

对于高负载系统，可以考虑：

1. 增加数据库连接池大小：

```ini
[database]
pool_size = 10  # 增加连接池大小
```

2. 启用数据缓存：
   - 添加Redis等缓存服务
   - 在热门请求路径上实现缓存

3. 负载均衡：
   - 使用Nginx上游服务器组实现负载均衡
   - 部署多个应用实例

### 安全增强

为提高系统安全性，请考虑以下配置：

1. 启用HTTPS（使用Let's Encrypt）：

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

2. 加强MySQL安全性：

```bash
# 限制MySQL只监听本地连接
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# 添加或确保以下行：
# bind-address = 127.0.0.1
```

3. 设置防火墙规则：

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## 变更日志

### 版本2.1.1 (2025-05-20)
- 修复了data_spider/create_target_table.py中try块缺少except/finally子句的问题
- 修复了web_server/main.py中update_user_info方法的缩进错误
- 优化了Python依赖管理，添加了对MySQLdb模块的替代方案
- 改进了低端口绑定权限检测逻辑，支持更多复杂环境
- 更新了脚本缩进问题修复工具

### 版本2.1.0 (2025-05-15)
- 添加了统一部署脚本`unified_deploy.sh`
- 增强了日志管理和备份功能
- 添加了健康检查系统
- 改进了错误诊断和修复工具
- 增加了微信公众号调试工具
- 修复了低端口绑定权限问题，支持符号链接和authbind备选方案
- 修复了Python脚本缩进问题，解决了TabError错误

### 版本2.0.1 (2025-05-10)
- 修复了外部管理的Python环境问题
- 改进了数据库初始化流程
- 提高了部署脚本的健壮性
- 添加了更多排障指南

### 版本2.0.0 (2025-05-01)
- 全面更新部署文档
- 添加了自动部署脚本
- 提供了详细的排障和维护指南
- 优化了系统配置