-- SPDX-License-Identifier: MIT
--
-- WorkBuddy2API 的 LuCI 入口：在「服务」菜单下挂一个状态页和一个设置页。
-- 状态页用模板渲染（要放启停按钮和日志，CBI 做这个别扭），设置页走 CBI。

module("luci.controller.workbuddy2api", package.seeall)

local fs   = require "nixio.fs"
local sys  = require "luci.sys"
local http = require "luci.http"
local disp = require "luci.dispatcher"

function index()
	-- 网关本体没装时不显示菜单，避免点进去一片空白
	if not fs.access("/etc/config/workbuddy2api") then
		return
	end

	local page = entry({"admin", "services", "workbuddy2api"},
		alias("admin", "services", "workbuddy2api", "status"), _("WorkBuddy2API"), 60)
	page.dependent = false
	page.acl_depends = { "luci-app-workbuddy2api" }

	entry({"admin", "services", "workbuddy2api", "status"},
		view("workbuddy2api/status"), _("运行状态"), 10).leaf = true

	entry({"admin", "services", "workbuddy2api", "config"},
		cbi("workbuddy2api/config"), _("设置"), 20).leaf = true

	entry({"admin", "services", "workbuddy2api", "action"},
		post("action_service")).leaf = true
end

-- 启停/自启开关统一走这里，做完跳回状态页。
-- 全部用绝对路径调用 init.d，不依赖 PATH。
function action_service()
	local what = http.formvalue("action")

	if what == "start" then
		sys.call("/etc/init.d/workbuddy2api start >/dev/null 2>&1")
	elseif what == "stop" then
		sys.call("/etc/init.d/workbuddy2api stop >/dev/null 2>&1")
	elseif what == "restart" then
		sys.call("/etc/init.d/workbuddy2api restart >/dev/null 2>&1")
	elseif what == "enable" then
		sys.call("/etc/init.d/workbuddy2api enable >/dev/null 2>&1")
	elseif what == "disable" then
		sys.call("/etc/init.d/workbuddy2api disable >/dev/null 2>&1")
	end

	http.redirect(disp.build_url("admin/services/workbuddy2api/status"))
end
