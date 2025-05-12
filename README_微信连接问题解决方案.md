# 电影推荐系统微信公众号连接问题解决方案

## 问题描述

在部署电影推荐系统时遇到以下关键问题：

1. 微信公众号无法正常连接到服务器，HTTP返回非200状态码
2. 数据处理脚本执行失败，显示MySQL访问被拒绝（Access denied for user 'root'@'localhost'）
3. 端口80被占用，导致服务无法正常启动
4. 健康检查端点(Health类)缩进错误，导致服务无法启动

## 问题原因分析

### 1. 微信连接问题

微信公众号服务器验证机制要求：
- HTTP状态码必须为200
- 返回内容必须是微信服务器发送的原始echostr参数值
- 任何异常导致的非200响应都会使验证失败

原系统代码中存在以下问题：
- web.py框架在遇到异常时直接返回500状态码
- 没有全局异常处理机制确保始终返回200状态码
- 没有健康检查端点用于验证服务状态

### 2. 数据库连接问题

MySQL 8.0及更高版本默认使用`caching_sha2_password`认证插件，这可能导致：
- root用户的默认认证方式更加严格
- `Access denied for user 'root'@'localhost'`错误
- 某些旧版客户端无法连接到MySQL服务器

### 3. 端口占用问题

端口80是特权端口：
- 需要root权限或特殊权限才能绑定
- 可能被其他服务（如Apache/Nginx）占用
- 在部署过程中检测到端口已被占用

### 4. 健康检查端点缩进问题

Python对缩进非常敏感，在添加健康检查端点时：
- 添加的`Health`类缩进不正确
- 导致出现`IndentationError: expected an indented block after class definition`错误
- 服务无法启动，自动重启但始终失败

## 解决方案

我们已经在`unified_deploy.sh`脚本中集成了以下解决方案：

### 1. 微信连接问题修复

1. **添加全局异常处理**：
   - 在web.py处理程序中添加`handle_wechat_error`方法
   - 确保所有异常情况下都返回200状态码
   - 正确返回微信echostr参数值

2. **健康检查端点**：
   - 添加`/health`端点，始终返回200状态码和"OK"
   - 便于监控和诊断服务状态

3. **微信测试工具**：
   - 创建`wechat_debug.py`脚本模拟微信服务器验证请求
   - 用于验证和诊断微信连接问题

### 2. 数据库连接问题修复

1. **重置root用户权限**：
   - 修改`mysql.user`表中root用户的认证插件为`mysql_native_password`
   - 允许root用户从任何主机连接（%）
   - 根据需要重置root密码

2. **安全模式重置**：
   - 如果无法正常连接，使用`skip-grant-tables`模式启动MySQL
   - 重置root用户权限和密码
   - 确保数据处理脚本能够正常连接数据库

### 3. 端口占用问题修复

1. **主动释放端口**：
   - 检测占用80端口的进程
   - 尝试终止占用进程，释放80端口
   - 如果成功释放，直接使用80端口

2. **低端口绑定权限**：
   - 使用`setcap`为Python解释器授予低端口绑定权限
   - 处理Python解释器符号链接情况
   - 支持直接使用80端口而无需root权限

3. **备选方案**：
   - 如果端口无法释放，自动配置Nginx反向代理
   - 内部使用高端口（如8080），外部使用80端口
   - 确保微信请求正确转发

### 4. 健康检查端点缩进修复

1. **修复Python缩进错误**：
   - 修正`Health`类和方法的缩进
   - 确保`def GET(self)`方法正确缩进
   - 修复`web.header`和`return`语句的缩进

2. **彻底重建健康检查**：
   - 如果简单修复不成功，完全重建Health类
   - 重新配置URL路由，确保正确匹配
   - 添加独立的Health类到文件末尾

## 使用方法

### 部署系统

运行统一部署脚本，已集成所有修复功能：

```bash
sudo bash scripts/unified_deploy.sh
```

### 手动修复微信连接

如果只需修复微信连接问题：

```bash
sudo bash fix_wechat_conn.sh
```

### 修复健康检查端点缩进问题

如果遇到健康检查端点缩进错误：

```bash
sudo bash fix_health_indentation.sh
```

### 测试微信连接

使用测试脚本验证微信连接：

```bash
# 测试微信验证机制
python3 scripts/wechat_debug.py --url http://your_server_ip --validate

# 测试健康检查端点
python3 scripts/wechat_debug.py --url http://your_server_ip --health

# 模拟发送消息
python3 scripts/wechat_debug.py --url http://your_server_ip --message "测试消息"
```

## 故障诊断

如果微信连接仍有问题，请检查：

1. 确认服务正在运行：
   ```bash
   systemctl status movie-recommender.service
   ```

2. 查看服务日志：
   ```bash
   journalctl -u movie-recommender.service -f
   ```

3. 检查网络连接：
   ```bash
   curl -v http://localhost/health
   ```

4. 检查Nginx配置（如使用反向代理）：
   ```bash
   nginx -t
   systemctl status nginx
   ```

5. 检查防火墙设置：
   ```bash
   ufw status
   ```

6. 检查Python语法错误：
   ```bash
   # 检查语法错误但不执行代码
   python3 -m py_compile /opt/recommender/web_server/main.py
   ```

如有进一步问题，请联系技术支持。 