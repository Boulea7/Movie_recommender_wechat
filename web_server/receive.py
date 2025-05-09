#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import xml.etree.ElementTree as ET

def parse_xml(web_data):
	if len(web_data) == 0:
		return None
	
	# 确保web_data是字节类型
	if isinstance(web_data, str):
		web_data = web_data.encode('utf-8')
	
	xmlData = ET.fromstring(web_data)
	msg_type = xmlData.find('MsgType').text
	if msg_type == 'text':
		return TextMsg(xmlData)
	elif msg_type == 'image':
		return ImageMsg(xmlData)
	elif msg_type == 'event':
		return EventMsg(xmlData)

class Msg(object):
	def __init__(self, xmlData):
		self.ToUserName = xmlData.find('ToUserName').text
		self.FromUserName = xmlData.find('FromUserName').text
		self.CreateTime = xmlData.find('CreateTime').text
		self.MsgType = xmlData.find('MsgType').text

class TextMsg(Msg):
	def __init__(self, xmlData):
		Msg.__init__(self, xmlData)
		content_elem = xmlData.find('Content')
		self.Content = content_elem.text if content_elem is not None else ""
		self.MsgId = xmlData.find('MsgId').text

class ImageMsg(Msg):
	def __init__(self, xmlData):
		Msg.__init__(self, xmlData)
		self.PicUrl = xmlData.find('PicUrl').text
		self.MediaId = xmlData.find('MediaId').text
		self.MsgId = xmlData.find('MsgId').text

class EventMsg(Msg):
	def __init__(self, xmlData):
		Msg.__init__(self, xmlData)
		self.Event = xmlData.find('Event').text
		# 某些事件可能没有EventKey字段
		eventKey = xmlData.find('EventKey')
		self.EventKey = eventKey.text if eventKey is not None else "" 