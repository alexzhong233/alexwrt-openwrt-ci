'use strict';
'require form';

var m, s, o;

m = new form.Map('workbuddy2api', _('WorkBuddy2API 设置'),
	_('账号、用量和 OAuth 授权都在管理面板里操作，这里只管网关本身的启动参数。'));

s = m.section(form.NamedSection, 'main', 'workbuddy2api', _('基本设置'));
s.addremove = false;

o = s.option(form.Value, 'host', _('监听地址'));
o.datatype = 'ipaddr';
o.rmempty = false;
o.default = '0.0.0.0';
o.description = _('0.0.0.0 表示所有网卡都能访问。只在内网用时保持默认即可。');

o = s.option(form.Value, 'port', _('监听端口'));
o.datatype = 'port';
o.rmempty = false;
o.default = '8788';
o.description = _('面板和 API 都走这个端口。客户端填 Base URL 时用 http://路由器IP:端口/v1。');

o = s.option(form.Value, 'panel_password', _('面板密码'));
o.password = true;
o.rmempty = true;
o.description = _('留空表示不改动，沿用面板里设置的密码。一旦填了值，每次启动都会把它写回面板，'
	+ '面板里改的密码重启后会变回这里的值。首次安装默认密码是 admin，建议尽快设一个。');

o = s.option(form.Value, 'api_key', _('固定 API Key'));
o.password = true;
o.rmempty = true;
o.description = _('客户端用的 Bearer Token。留空则由面板自动生成并持久化到 settings.json，重启不丢；'
	+ '填了值则以这里为准，适合多台客户端统一配置。');

o = s.option(form.Value, 'stats_ttl', _('统计缓存 TTL（秒）'));
o.datatype = 'uinteger';
o.rmempty = true;
o.default = '900';
o.description = _('面板每 5 秒轮询一次，缓存过期要全量重扫用量日志。默认 900 秒配合预热器让面板点开即是毫秒级。'
	+ '调小 = 数字更实时但更吃 CPU。');

o = s.option(form.Flag, 'warm', _('面板缓存预热'));
o.rmempty = false;
o.default = '1';
o.description = _('由 cron 每 2 分钟预跑一遍面板的统计接口，切页不用等。关闭后面板仍可用，只是首次打开会卡十几秒。');

s = m.section(form.NamedSection, 'main', 'workbuddy2api', _('数据目录'));
s.addremove = false;

o = s.option(form.Value, 'accounts_dir', _('账号目录'));
o.rmempty = true;
o.default = '/etc/workbuddy2api/accounts';
o.description = _('存 OAuth token，属敏感数据。默认位置已加入 sysupgrade 保留列表，改到别处就不会自动保留了。');

o = s.option(form.Value, 'usage_dir', _('用量目录'));
o.rmempty = true;
o.default = '/etc/workbuddy2api/usage';
o.description = _('存请求用量日志，面板的统计和定价估算都读这里。');

return m;
