'use strict';
'require view';
'require fs';
'require ui';
'require uci';

var SERVICE = '/etc/init.d/workbuddy2api';

function svc(action) {
	return fs.exec(SERVICE, [ action ]);
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('workbuddy2api').catch(function() { return null; }),

			// 进程是否在跑：rc.common 的 status 子命令返回 0/1
			svc('status')
				.then(function(r) { return r.code === 0; })
				.catch(function() { return false; }),

			// 开机自启：rc.common 的 enabled 子命令返回 0/1，比判断 rc.d 软链可靠
			svc('enabled')
				.then(function(r) { return r.code === 0; })
				.catch(function() { return false; }),

			fs.exec('/sbin/logread', [ '-e', 'workbuddy2api' ])
				.then(function(r) { return (r.stdout || '').trim(); })
				.catch(function() { return ''; })
		]);
	},

	handleAction: function(action) {
		return svc(action).then(function() {
			window.location.reload();
		});
	},

	render: function(data) {
		var running = data[1];
		var enabled = data[2];
		var log = data[3];

		var host = uci.get('workbuddy2api', 'main', 'host') || '0.0.0.0';
		var port = uci.get('workbuddy2api', 'main', 'port') || '8788';

		// 绑 0.0.0.0 时用浏览器当前的主机名，避免给出一个点不开的地址
		var panelHost = (host === '0.0.0.0' || host === '::' || host === '')
			? window.location.hostname : host;
		var panelUrl = 'http://' + panelHost + ':' + port + '/';

		var row = function(label, value, hint) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '25%' }, [ label ]),
				E('td', { 'class': 'td left' }, [
					value,
					hint ? E('div', { 'class': 'cbi-value-description' }, [ hint ]) : ''
				])
			]);
		};

		var btn = function(action, label, style) {
			return E('button', {
				'class': 'btn cbi-button ' + style,
				'click': ui.createHandlerFn(this, function() {
					return this.handleAction(action);
				}.bind(this))
			}, [ label ]);
		}.bind(this);

		var statusCell = running
			? E('span', { 'style': 'color:#4caf50;font-weight:bold' }, [ '● 运行中' ])
			: E('span', { 'style': 'color:#9e9e9e;font-weight:bold' }, [ '● 已停止' ]);

		var enabledCell = enabled
			? E('span', { 'style': 'color:#4caf50' }, [ '已启用' ])
			: E('span', { 'style': 'color:#ff9800' }, [ '未启用' ]);

		var logBox = E('pre', {
			'style': 'max-height:320px;overflow:auto;padding:8px;border-radius:4px;font-size:12px;line-height:1.5;background:rgba(128,128,128,0.12);white-space:pre-wrap;word-break:break-all'
		}, [ log !== '' ? log : '(no log entries)' ]);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ 'WorkBuddy2API' ]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ '服务状态' ]),
				E('table', { 'class': 'table' }, [
					row('运行状态', statusCell),
					row('开机自启', enabledCell),
					row('监听地址', E('code', {}, [ host + ':' + port ])),
					row('管理面板',
						E('a', { 'href': panelUrl, 'target': '_blank', 'rel': 'noopener' }, [ panelUrl ]),
						'账号管理、用量统计、OAuth 授权都在面板里完成'),
					row('配置目录', E('code', {}, [ '/etc/config/workbuddy2api' ])),
					row('数据目录', E('code', {}, [ '/etc/workbuddy2api/' ]),
						'已加入 sysupgrade 保留列表，升级不丢账号')
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ '服务控制' ]),
				E('div', { 'class': 'cbi-page-actions' }, [
					running
						? btn('stop', '停止', 'cbi-button-reset')
						: btn('start', '启动', 'cbi-button-apply'),
					running ? btn('restart', '重启', 'cbi-button-action') : '',
					enabled
						? btn('disable', '取消开机自启', 'cbi-button-reset')
						: btn('enable', '设为开机自启', 'cbi-button-apply')
				]),
				E('div', { 'class': 'cbi-value-description' }, [
					'默认不开机自启。需要常驻时先「设为开机自启」再「启动」。',
					'网关由 procd 托管，崩溃会自动拉起，不需要手动 nohup。'
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ '最近日志' ]),
				logBox,
				E('div', { 'class': 'cbi-value-description' }, [
					'取自 logread -e workbuddy2api，最近 20 行左右的滚动输出。'
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
