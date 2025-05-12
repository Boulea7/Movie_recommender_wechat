# 电影推荐系统

这是一个基于微信公众号的电影推荐系统，使用协同过滤算法为用户提供个性化电影推荐。

## 功能特点

- **搜索功能**：用户可以通过公众号搜索电影信息，支持模糊搜索和类别搜索
- **评价功能**：用户可以对电影进行评分（0-10分），系统记录用户偏好
- **推荐功能**：系统基于协同过滤算法为用户推荐电影，考虑用户历史评分和兴趣类别
- **错误处理**：完善的错误处理机制，即使在突发情况下仍能提供服务
- **日志系统**：详细的日志记录，便于故障排查和系统优化

## 系统架构

- **前端**：微信公众号
- **后端**：基于web.py的Web服务
- **数据库**：MySQL
- **算法**：协同过滤推荐算法
- **配置管理**：配置文件支持系统灵活配置
- **连接池**：数据库连接池和自动重连机制

## 快速部署指南

以下是在纯净系统上快速部署电影推荐系统的步骤：

```bash
# 1. 更新系统并安装Git
sudo apt update
sudo apt install -y git

# 2. 克隆项目代码
git clone https://github.com/your_username/recommender.git /tmp/recommender

# 3. 执行部署脚本
cd /tmp/recommender
sudo chmod +x scripts/*.sh
sudo bash scripts/deploy.sh

# 4. 验证部署
curl http://localhost/
sudo systemctl status movie-recommender.service
```

如遇问题，可使用自动诊断工具：

```bash
sudo bash /opt/recommender/scripts/troubleshoot.sh -f
```

详细部署步骤请参考[部署文档](deployment.md)。

## 交互方式

用户可以通过以下命令与公众号交互：

1. **搜索电影**：
   - 直接发送电影名称：`战狼2`
   - 指定搜索：`搜索 战狼2`
   - 类别搜索：`类别 科幻`
   - 导演搜索：`导演 张艺谋`

2. **评价电影**：
   - 发送：`评价 电影名 分数`（分数范围0-10）
   - 例如：`评价 战狼2 8`

3. **获取推荐**：
   - 基本推荐：发送`推荐`
   - 基于类别推荐：`推荐 科幻`
   - 指定数量：`推荐 5部`

4. **获取使用帮助**：发送`怎么用`或`帮助`

## 系统特性

### 健壮性设计

- **数据库连接池**：减少连接开销，提供连接复用
- **自动重连机制**：网络故障时自动尝试重连
- **配置文件**：避免硬编码，便于环境迁移
- **详细日志**：记录系统运行状态和错误信息
- **定时备份**：自动备份数据，防止数据丢失

### 安全性考虑

- **输入验证**：验证用户输入，防止SQL注入
- **参数化查询**：使用参数化查询执行SQL语句
- **错误处理**：隐藏错误细节，防止信息泄露
- **数据库权限**：使用最小权限原则配置数据库账户

## 数据模型

系统使用以下数据表存储信息：

1. **电影信息表(douban_movie)**：存储电影基本信息，包括标题、评分、链接、上映时间、产地、演员、导演、类别等
2. **用户信息表(user_info)**：存储用户基本信息，包括微信ID、注册时间等
3. **用户搜索记录表(seek_movie)**：记录用户的搜索历史
4. **用户评分表(like_movie)**：存储用户对电影的评分

## 端口配置

微信公众号要求使用80端口通信。本系统提供两种配置方式：

1. **直接使用80端口**（默认方式）：
   ```bash
   sudo bash /opt/recommender/scripts/update_service.sh
   ```

2. **使用Nginx反向代理**（推荐生产环境使用）：
   ```bash
   sudo bash /opt/recommender/scripts/setup_nginx.sh
   ```

## 项目结构

```
recommender/
├── README.md             # 项目说明文档
├── requirements.txt      # 项目依赖
├── deployment.md         # 部署文档
├── progress.md           # 项目进度文档
├── config/               # 配置文件目录
│   └── database.conf     # 数据库和系统配置
├── scripts/              # 部署脚本
│   ├── deploy.sh         # 自动部署脚本
│   ├── init_database.sh  # 数据库初始化脚本
│   ├── update_service.sh # 服务更新脚本
│   ├── setup_nginx.sh    # Nginx配置脚本 
│   ├── troubleshoot.sh   # 问题诊断与修复脚本
│   ├── restart_service.sh# 服务重启脚本
│   └── check_port.sh     # 端口检查脚本
├── sql/                  # SQL脚本
│   └── init_tables.sql   # 初始表结构创建脚本
├── web_server/           # Web服务代码
│   ├── __init__.py       # 包初始化文件
│   ├── main.py           # 主程序
│   ├── receive.py        # 消息接收处理
│   ├── reply.py          # 消息回复处理
│   ├── config_parser.py  # 配置解析器
│   ├── db_manager.py     # 数据库连接管理器
│   └── logger.py         # 日志模块
├── data_spider/          # 数据爬虫
│   ├── create_target_table.py  # 创建目标表
│   └── douban.py         # 豆瓣数据爬虫
├── logs/                 # 日志目录
│   ├── web_server.log    # Web服务日志
│   └── error.log         # 错误日志
└── test_data/            # 测试数据
    └── sample_movies.sql # 样本电影数据
``` 

## 系统维护

### 服务管理命令

```bash
# 启动服务
sudo systemctl start movie-recommender.service

# 重启服务
sudo systemctl restart movie-recommender.service

# 停止服务
sudo systemctl stop movie-recommender.service

# 查看服务状态
sudo systemctl status movie-recommender.service

# 查看服务日志
sudo journalctl -u movie-recommender.service -f

# 检查端口
sudo netstat -tuln | grep 80
```

### 问题诊断与修复

系统提供了自动诊断与修复工具：

```bash
# 诊断模式（仅显示问题）
sudo bash /opt/recommender/scripts/troubleshoot.sh

# 诊断并提示修复
sudo bash /opt/recommender/scripts/troubleshoot.sh -f

# 诊断并自动修复所有问题
sudo bash /opt/recommender/scripts/troubleshoot.sh -fy
```

此工具会自动检查：
- 安装目录和文件完整性
- 配置文件正确性
- 系统服务状态
- 端口占用情况
- 防火墙配置
- 服务可访问性
- 日志配置
- 数据库连接状态

### 数据库操作

```bash
# 连接到系统数据库
mysql -u douban_user -p"MySQL_20050816Zln@233" douban

# 备份数据库
sudo mysqldump -u root -p douban > /opt/recommender_backups/douban_$(date +%Y%m%d).sql

# 从备份恢复
sudo mysql -u root -p douban < /opt/recommender_backups/douban_20250510.sql
```

## 更新日志

### 版本 2.0.0 (2025-05-10)
- 全面重构部署流程，优化系统稳定性
- 新增自动诊断与修复工具
- 优化服务配置，解决端口绑定问题
- 添加Nginx反向代理支持
- 完善系统文档

### 版本 1.1.0 (2023-05-25)
- 增加配置文件支持
- 添加数据库连接池
- 完善错误处理和日志系统
- 丰富电影数据库
- 添加系统健康检查
- 增强推荐算法

### 版本 1.0.0 (2023-05-20)
- 初始版本发布
- 基本搜索和推荐功能
- 微信公众号接口

## 最近更新

### 2025-05-10 系统部署与稳定性增强

1. **部署流程重构**
   - 重写部署文档和脚本，支持纯净系统一键部署
   - 添加自动诊断与修复工具(troubleshoot.sh)，简化故障排查
   - 增强部署脚本健壮性，智能处理常见错误

2. **服务配置增强**
   - 增强systemd服务定义，确保绑定特权端口和自动重启
   - 优化部署脚本，自动处理防火墙和端口配置
   - 完善日志记录，便于问题诊断

3. **微信公众号兼容性**
   - 确保正确使用80端口，满足微信公众号要求
   - 提供Nginx反向代理方案，解决端口冲突问题
   - 添加服务可访问性自动检测

4. **文档系统更新**
   - 全面重构部署文档，提供详细的步骤和排错指南
   - 更新README.md，包含快速部署指南和维护命令
   - 增加系统架构和数据模型说明

### 2025-05-09 端口配置和微信集成优化

1. **端口配置优化**
   - 修复服务默认使用8080端口的问题，确保正确使用配置文件中的80端口设置
   - 添加端口绑定权限，确保服务可以绑定特权端口(80)
   - 提供Nginx反向代理配置方案，解决端口冲突问题

2. **防火墙配置**
   - 添加防火墙配置说明，确保80端口可被外部访问
   - 提供端口检查和故障排查步骤

3. **服务配置优化**
   - 更新systemd服务配置，确保服务自动重启和日志记录
   - 添加update_service.sh脚本，简化服务配置更新流程

4. **文档更新**
   - 在部署文档中添加详细的端口配置和Nginx反向代理说明
   - 新增端口故障排查指南，帮助用户解决网络访问问题

## 贡献者

- 电影推荐系统团队 - 开发与维护 