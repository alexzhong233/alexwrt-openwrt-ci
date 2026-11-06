-- SPDX-License-Identifier: MIT
--
-- WorkBuddy2API 设置页。只映射 /etc/config/workbuddy2api 里已有的字段，
-- 不新增上游不认识的键，避免网关启动时读到意料之外的值。

local sys = require "luci.sys"

local m, s, o

m = Map("workbuddy2api", "WorkBuddy2API 设置",
	"改完保存会自动重启服务（仅在服务运行中时）。账号、用量和 OAuth 授权都在管理面板里操作，这里只管网关本身的启动参数。")

-- 「main」是上游固定的 section 名，网关只读这个
s = m:section(NamedSection, "main", "workbuddy2api", "基本设置")
s.addremove = false

o = s:option(Value, "host", "监听地址")
o.datatype = "ipaddr"
o.rmempty = false
o.default = "0.0.0.0"
o.description = "0.0.0.0 表示所有网卡都能访问。如果只想局域网内用，保持默认即可。"

o = s:option(Value, "port", "监听端口")
o.datatype = "port"
o.rmempty = false
o.default = "8788"
o.description = "面板和 API 都走这个端口，客户端填 Base URL 时要用 http://路由器IP:端口/v1。"

o = s:option(Value, "panel_password", "面板密码")
o.password = true
o.rmempty = true
o.description = "留空表示不改动，沿用面板里设置的密码。一旦在这里填了值，每次启动都会把它写回面板，"
	.. "面板里改的密码重启后会变回这里的值。首次安装默认密码是 admin，建议尽快在本页设一个。"
	.. "留空与不设置等价，不会把面板密码清空。"

o = s:option(Value, "api_key", "固定 API Key")
o.password = true
o.rmempty = true
o.description = "客户端用的 Bearer Token。留空则由面板自动生成并持久化到 accounts/settings.json，重启不丢；"
	.. "填了值则以这里为准，适合多台客户端统一配置。"

o = s:option(Value, "stats_ttl", "统计缓存 TTL（秒）")
o.datatype = "uinteger"
o.rmempty = true
o.default = "900"
o.description = "面板每 5 秒轮询一次，每次缓存过期都要全量重扫用量日志。"
	.. "这台机器上 2 万行约需十几秒，所以默认 900 秒配合下面的预热器让面板点开即是毫秒级。"
	.. "调小 = 数字更实时但更吃 CPU；用了每日限额功能的话别调太大。"

o = s:option(Flag, "warm", "面板缓存预热")
o.rmempty = false
o.default = "1"
o.description = "开启后由 cron 每 2 分钟预跑一遍面板的统计接口，切页不用等。"
	.. "关闭后面板仍可用，只是缓存过期后第一次打开会卡十几秒。"

s = m:section(NamedSection, "main", "workbuddy2api", "数据目录")
s.addremove = false

o = s:option(Value, "accounts_dir", "账号目录")
o.rmempty = true
o.default = "/etc/workbuddy2api/accounts"
o.description = "存 OAuth token，属敏感数据，权限应为 700。默认位置已加入 sysupgrade 保留列表，"
	.. "改到别处就不会自动保留了。"

o = s:option(Value, "usage_dir", "用量目录")
o.rmempty = true
o.default = "/etc/workbuddy2api/usage"
o.description = "存请求用量日志，面板的统计和定价估算都读这里。"

-- 保存后自动重启，省得用户再回状态页点一次
function m.on_after_commit(self)
	if sys.call("pgrep -f 'wb_proxy' >/dev/null 2>&1") == 0 then
		sys.call("/etc/init.d/workbuddy2api restart >/dev/null 2>&1")
	end
end

return m
