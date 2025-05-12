#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
微信公众号调试工具
用于测试微信服务器连接和功能
作者：电影推荐系统团队
日期：2025-05-10
"""

import os
import sys
import requests
import hashlib
import time
import argparse
import json
import xml.etree.ElementTree as ET
from urllib.parse import urlencode

# 添加项目根目录到路径
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(current_dir)
sys.path.append(project_root)

# 导入配置解析器
try:
    from web_server.config_parser import ConfigParser
except ImportError:
    print("错误: 无法导入配置解析器，请确保项目结构正确")
    sys.exit(1)

class WeChatDebugger:
    """微信公众号调试工具"""
    
    def __init__(self, config_path=None, url=None):
        """
        初始化微信调试工具
        
        参数:
            config_path: 配置文件路径
            url: 服务器URL，如果不提供则从配置中获取
        """
        # 获取配置
        self.config_parser = ConfigParser(config_path)
        try:
            self.service_config = self.config_parser.get_section('service')
        except Exception as e:
            print(f"警告: 使用get_section方法失败: {e}")
            self.service_config = self.config_parser.get_service_config()
        
        # 获取服务器信息
        self.token = self.service_config.get('token', 'HelloMovieRecommender')
        self.url = url or f"http://{self._get_server_ip()}"
        
        # 输出配置信息
        print("微信公众号调试工具初始化成功!")
        print(f"服务器URL: {self.url}")
        print(f"Token: {self.token}")
    
    def _get_server_ip(self):
        """获取服务器IP地址"""
        try:
            # 尝试通过命令获取
            import socket
            hostname = socket.gethostname()
            ip = socket.gethostbyname(hostname)
            return ip
        except:
            # 默认使用localhost
            return "localhost"
    
    def validate_server(self):
        """
        验证服务器连接与配置
        模拟微信服务器发送验证请求
        """
        # 生成随机字符串
        timestamp = str(int(time.time()))
        nonce = "123456789"
        echostr = "test_echo_string"
        
        # 生成签名
        sign_list = [self.token, timestamp, nonce]
        sign_list.sort()
        sign_str = ''.join(sign_list)
        signature = hashlib.sha1(sign_str.encode()).hexdigest()
        
        # 构建验证URL
        params = {
            'signature': signature,
            'timestamp': timestamp,
            'nonce': nonce,
            'echostr': echostr
        }
        verify_url = f"{self.url}/?{urlencode(params)}"
        
        print("\n====== 开始验证服务器配置 ======")
        print(f"验证URL: {verify_url}")
        
        # 发送请求
        try:
            start_time = time.time()
            response = requests.get(verify_url, timeout=10)
            end_time = time.time()
            
            # 输出结果
            print(f"响应时间: {end_time - start_time:.3f}秒")
            print(f"响应状态码: {response.status_code}")
            
            if response.status_code == 200:
                if response.text == echostr:
                    print(f"验证成功! 服务器返回了正确的echostr: {response.text}")
                else:
                    print(f"验证失败! 服务器应返回: '{echostr}'，实际返回: '{response.text}'")
            else:
                print(f"验证失败! 服务器返回了非200状态码: {response.status_code}")
                print(f"响应内容: {response.text}")
        except requests.exceptions.ConnectionError:
            print("连接错误! 无法连接到服务器，请检查URL和网络")
        except requests.exceptions.Timeout:
            print("连接超时! 服务器响应时间过长")
        except Exception as e:
            print(f"验证过程出现错误: {e}")
    
    def send_test_message(self, msg_type="text", content="您好，这是一条测试消息"):
        """
        发送测试消息
        模拟用户发送消息
        
        参数:
            msg_type: 消息类型，支持text, image
            content: 消息内容
        """
        # 生成消息XML
        from_user = "test_user"
        to_user = "gh_123456789"  # 公众号原始ID
        timestamp = str(int(time.time()))
        
        if msg_type == "text":
            xml_content = f"""
            <xml>
                <ToUserName><![CDATA[{to_user}]]></ToUserName>
                <FromUserName><![CDATA[{from_user}]]></FromUserName>
                <CreateTime>{timestamp}</CreateTime>
                <MsgType><![CDATA[text]]></MsgType>
                <Content><![CDATA[{content}]]></Content>
                <MsgId>1234567890123456</MsgId>
            </xml>
            """
        elif msg_type == "image":
            xml_content = f"""
            <xml>
                <ToUserName><![CDATA[{to_user}]]></ToUserName>
                <FromUserName><![CDATA[{from_user}]]></FromUserName>
                <CreateTime>{timestamp}</CreateTime>
                <MsgType><![CDATA[image]]></MsgType>
                <PicUrl><![CDATA[http://example.com/test.jpg]]></PicUrl>
                <MediaId><![CDATA[media_id]]></MediaId>
                <MsgId>1234567890123456</MsgId>
            </xml>
            """
        else:
            print(f"不支持的消息类型: {msg_type}")
            return
        
        # 生成签名
        nonce = "123456789"
        sign_list = [self.token, timestamp, nonce]
        sign_list.sort()
        sign_str = ''.join(sign_list)
        signature = hashlib.sha1(sign_str.encode()).hexdigest()
        
        # 构建URL
        params = {
            'signature': signature,
            'timestamp': timestamp,
            'nonce': nonce
        }
        message_url = f"{self.url}/?{urlencode(params)}"
        
        print("\n====== 发送测试消息 ======")
        print(f"消息类型: {msg_type}")
        print(f"目标URL: {message_url}")
        print(f"发送内容: {content}")
        
        # 发送请求
        try:
            headers = {'Content-Type': 'application/xml'}
            response = requests.post(message_url, data=xml_content, headers=headers, timeout=10)
            
            # 输出结果
            print(f"响应状态码: {response.status_code}")
            
            if response.status_code == 200:
                print("消息发送成功!")
                
                # 解析响应
                try:
                    if response.text.strip():
                        root = ET.fromstring(response.text)
                        resp_msg_type = root.find('MsgType').text
                        
                        if resp_msg_type == 'text':
                            resp_content = root.find('Content').text
                            print(f"服务器响应(文本): {resp_content}")
                        else:
                            print(f"服务器响应(类型: {resp_msg_type}): {response.text}")
                    else:
                        print("服务器没有返回消息")
                except Exception as e:
                    print(f"解析响应出错: {e}")
                    print(f"原始响应: {response.text}")
            else:
                print(f"消息发送失败! 服务器返回了非200状态码: {response.status_code}")
                print(f"响应内容: {response.text}")
        except Exception as e:
            print(f"消息发送过程出现错误: {e}")
    
    def check_system_status(self):
        """检查系统状态"""
        print("\n====== 系统状态检查 ======")
        
        # 检查服务
        import subprocess
        try:
            result = subprocess.run(
                "systemctl is-active movie-recommender.service", 
                shell=True, 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE
            )
            if result.stdout.decode().strip() == "active":
                print("电影推荐系统服务状态: 运行中")
            else:
                print("电影推荐系统服务状态: 未运行")
                print("尝试查看服务错误:")
                status = subprocess.run(
                    "systemctl status movie-recommender.service | head -20", 
                    shell=True, 
                    stdout=subprocess.PIPE, 
                    stderr=subprocess.PIPE
                )
                print(status.stdout.decode())
        except:
            print("无法检查服务状态，可能不是在Linux系统上运行")
        
        # 检查端口
        try:
            result = subprocess.run(
                "netstat -tuln | grep :80", 
                shell=True, 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE
            )
            if result.stdout:
                print("端口80状态: 已被占用")
                print(result.stdout.decode())
            else:
                print("端口80状态: 未被占用")
        except:
            print("无法检查端口状态")
        
        # 检查Python环境
        import platform
        print(f"Python版本: {platform.python_version()}")
        
        # 检查重要模块
        modules = ["web", "pymysql", "requests", "lxml"]
        for module in modules:
            try:
                __import__(module)
                print(f"模块 {module}: 已安装")
            except ImportError:
                print(f"模块 {module}: 未安装")

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='微信公众号调试工具')
    parser.add_argument('--config', help='配置文件路径')
    parser.add_argument('--url', help='服务器URL')
    parser.add_argument('--validate', action='store_true', help='验证服务器配置')
    parser.add_argument('--send', help='发送测试消息')
    parser.add_argument('--msg-type', default='text', help='消息类型: text或image')
    parser.add_argument('--status', action='store_true', help='检查系统状态')
    
    args = parser.parse_args()
    
    # 初始化调试工具
    debugger = WeChatDebugger(config_path=args.config, url=args.url)
    
    # 根据参数执行操作
    if args.validate:
        debugger.validate_server()
    
    if args.send:
        debugger.send_test_message(msg_type=args.msg_type, content=args.send)
    
    if args.status:
        debugger.check_system_status()
    
    # 如果没有指定操作，显示交互式菜单
    if not (args.validate or args.send or args.status):
        while True:
            print("\n=== 微信公众号调试工具 ===")
            print("1. 验证服务器配置")
            print("2. 发送测试消息")
            print("3. 检查系统状态")
            print("0. 退出")
            
            choice = input("请选择操作: ")
            
            if choice == "1":
                debugger.validate_server()
            elif choice == "2":
                msg_type = input("请选择消息类型(text/image)，默认text: ") or "text"
                content = input("请输入消息内容: ") or "您好，这是一条测试消息"
                debugger.send_test_message(msg_type=msg_type, content=content)
            elif choice == "3":
                debugger.check_system_status()
            elif choice == "0":
                break
            else:
                print("无效选择，请重新输入")

if __name__ == "__main__":
    main() 