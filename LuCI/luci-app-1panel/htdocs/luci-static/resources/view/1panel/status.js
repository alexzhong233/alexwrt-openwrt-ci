'use strict';
'require view';
'require fs';
'require ui';
'require poll';

var TOOL = '/usr/libexec/1panel-ctl';

function call(args) {
	return fs.exec(TOOL, args).then(function(res) {
		var text = ((res && res.stdout) || '') + ((res && res.stderr) || '');

		return { code: res ? res.code : 1, text: text.replace(/\s+$/, '') };
	}).catch(function(err) {
		return { code: 1, text: '执行失败：' + (err && err.message ? err.message : err) };
	});
}

function parseStatus(text) {
	var out = {};

	(text || '').split('\n').forEach(function(line) {
		var idx = line.indexOf('=');

		if (idx > 0)
			out[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
	});

	return out;
}

function flag(value) {
	return String(value) === '1';
}

function badge(ok, okText, badText) {
	return E('span', { 'class': 'label ' + (ok ? 'success' : 'warning') }, [ ok ? okText : badText ]);
}

function muted(text) {
	return E('span', { 'class': 'cbi-value-description' }, [ text ]);
}

function link(url) {
	if (!url)
		return muted('—');

	return E('a', { 'href': url, 'target': '_blank', 'rel': 'noopener' }, [ url ]);
}

/* 表格用 CSS Grid 而不是 <table>：Argon/Aurora 这类主题对 th/td 有高特异性
 * 的 !important 规则，会把表头和数据行拆成不同盒模型导致列错位。两个 grid
 * 共用同一份 template-columns 就不受这些规则影响。 */
var GRID_CSS = [
	'.p1-wrap { overflow-x: auto; }',
	'.p1-grid { display: grid; grid-template-columns: 11rem minmax(14rem, 1fr); min-width: 30rem; }',
	'.p1-h { padding: .45rem .6rem; font-weight: bold;',
	'  border-bottom: 2px solid rgba(128,128,128,.35); }',
	'.p1-c { padding: .45rem .6rem; border-bottom: 1px solid rgba(128,128,128,.18); }',
	'.p1-actions .btn { margin-right: .5rem; margin-bottom: .5rem; }',
	'.p1-form { display: grid; grid-template-columns: 11rem minmax(12rem, 24rem);',
	'  gap: .5rem .8rem; align-items: center; }',
	'.p1-form input { width: 100%; box-sizing: border-box; }'
].join('\n');

return view.extend({
	load: function() {
		return call([ 'status' ]);
	},

	buildRows: function(st) {
		var installed = flag(st.installed);
		var running = flag(st.running);

		function row(label, value) {
			return [
				E('div', { 'class': 'p1-c' }, [ label ]),
				E('div', { 'class': 'p1-c' }, Array.isArray(value) ? value : [ value ])
			];
		}

		var rows = [];

		rows = rows.concat(row(_('状态'), installed
			? badge(running, _('运行中'), _('已停止'))
			: badge(false, '', _('未部署'))));

		rows = rows.concat(row(_('运行方式'), st.kind === 'moelin'
			? _('轻量版 moelin/1panel —— 镜像自带面板，启动快，系统类模块读的是容器内部')
			: _('完整版 linkease/istorepanel —— 容器内跑 systemd，系统/防火墙模块可用')));

		if (installed) {
			rows = rows.concat(row(_('版本'), st.version || muted(_('尚未初始化，点下面的「初始化 1Panel」'))));
			rows = rows.concat(row(_('容器'), E('code', {}, [ st.container || '—' ])));
			rows = rows.concat(row(_('镜像'), E('code', {}, [ st.image || '—' ])));
			rows = rows.concat(row(_('创建于'), st.created || '—'));
			rows = rows.concat(row(_('访问地址'), link(st.address)));
		}

		rows = rows.concat(row(_('监听端口'), st.port || '—'));
		rows = rows.concat(row(_('登录账号'), st.username || '—'));
		rows = rows.concat(row(_('入口路径'), st.entrance
			? E('code', {}, [ st.entrance ])
			: muted(_('未设置（首次启动时由容器自行生成，见日志）'))));
		rows = rows.concat(row(_('数据目录'), E('code', {}, [ st.datadir || '—' ])));

		return rows;
	},

	render: function(result) {
		var self = this;
		var st = parseStatus(result ? result.text : '');
		var grid = E('div', { 'class': 'p1-grid' });

		function fill(fresh) {
			while (grid.firstChild)
				grid.removeChild(grid.firstChild);

			self.buildRows(fresh).forEach(function(node) {
				grid.appendChild(node);
			});
		}

		fill(st);

		var out = E('pre', {
			'id': 'p1-out',
			'style': 'max-height:20rem;overflow:auto;white-space:pre-wrap;word-break:break-all;margin:0'
		}, [ _('（还没有执行任何操作）') ]);

		function setOut(text) {
			out.textContent = text || _('（无输出）');
		}

		function refresh() {
			return call([ 'status' ]).then(function(res) {
				var fresh = parseStatus(res.text);

				fill(fresh);

				/* 部署前是表单，部署后换成操作按钮，用整页重绘最省事。 */
				if (flag(fresh.installed) !== flag(st.installed)) {
					st = fresh;
					window.setTimeout(function() { location.reload(); }, 1200);
				}
			});
		}

		function run(args, label, reload) {
			setOut(_('正在执行：') + label + ' ...');

			return call(args).then(function(res) {
				setOut('$ 1panel-ctl ' + args.join(' ') + '\n\n' + (res.text || _('（无输出）')));

				if (reload)
					window.setTimeout(function() { location.reload(); }, 1500);

				return refresh();
			});
		}

		function actionButton(label, args, reload) {
			return E('button', {
				'class': 'btn cbi-button',
				'click': function(ev) {
					ev.preventDefault();
					return run(args, label, reload);
				}
			}, [ label ]);
		}

		/* ---- 未部署：安装表单 ---- */
		var installPanel;
		var installed = flag(st.installed);
		var running = flag(st.running);

		if (!installed) {
			function field(label, value, type, placeholder) {
				var input = E('input', {
					'type': type || 'text',
					'class': 'cbi-input-text',
					'placeholder': placeholder || '',
					'value': value || ''
				});

				return {
					input: input,
					nodes: [
						E('label', {}, [ label ]),
						input
					]
				};
			}

			var fPort = field(_('监听端口'), '10086');
			var fUser = field(_('登录账号'), '1panel');
			var fPass = field(_('登录密码'), '', 'password', _('8 位以上，别用 password'));
			var fEnt  = field(_('入口路径'), '', 'text', _('例如 panel-8x3k，别用 entrance'));
			var fDir  = field(_('数据目录'), st.datadir || '/mnt/sda1/Configs/1Panel');

			/* 完整版要在容器里跑 systemd，必须 host 网络、cgroupns=host、SYS_ADMIN；
			 * 轻量版镜像自带面板，docker run 就能用。两者数据布局不同，装完不能互换。 */
			var kindSel = E('select', { 'class': 'cbi-input-select' }, [
				E('option', { 'value': 'istore' },
					[ _('完整版 — linkease/istorepanel（容器内 systemd，功能接近裸机）') ]),
				E('option', { 'value': 'moelin' },
					[ _('轻量版 — moelin/1panel（镜像自带面板，启动快）') ])
			]);

			var kindNodes = [
				E('label', {}, [ _('运行方式') ]),
				kindSel
			];

			installPanel = E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('部署 1Panel') ]),
				E('div', { 'class': 'cbi-map-descr' }, [
					_('镜像用社区维护的 moelin/1panel（官方不发布 Docker 镜像）。容器以 host 网络运行，挂载 docker.sock 与数据目录。首次初始化需要 20-60 秒。')
				]),
				E('div', { 'class': 'p1-form', 'style': 'margin-top:1rem' },
					[].concat(kindNodes, fPort.nodes, fUser.nodes, fPass.nodes, fEnt.nodes, fDir.nodes)),
				E('div', { 'style': 'margin-top:1rem' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function(ev) {
							ev.preventDefault();

							if (!fPass.input.value || fPass.input.value.length < 8) {
								ui.addNotification(null, E('p', {}, [ _('密码至少 8 位') ]), 'warning');
								return;
							}

							if (fDir.input.value.indexOf('/mnt/') !== 0) {
								ui.addNotification(null, E('p', {}, [
									_('数据目录必须在 /mnt 下：1Panel 的数据库和应用都写在这里，放 overlay 会写满 flash，刷机也会丢。')
								]), 'warning');
								return;
							}

							return run([ 'install', fPort.input.value, fUser.input.value,
								fPass.input.value, fEnt.input.value, fDir.input.value, kindSel.value ],
								_('部署容器'), true);
						}
					}, [ _('部署') ])
				]),
				out
			]);
		}

		/* ---- 已部署：操作按钮 ---- */
		/* istore 镜像里的 1Panel 是运行时才装的：容器起来但 1pctl 还没有，
		 * 说明 reinstall.sh 没跑过。这时单独给一个「初始化」按钮，避免把
		 * 几百 MB 的下载塞进 docker run 里让页面超时。 */
		var ops = [
			running
				? actionButton(_('停止'), [ 'stop' ])
				: actionButton(_('启动'), [ 'start' ]),
			actionButton(_('重启'), [ 'restart' ]),
			actionButton(_('查看日志'), [ 'logs' ])
		];

		if (running && !st.version)
			ops.push(actionButton(_('初始化 1Panel'), [ 'bootstrap' ]));

		ops.push(E('a', {
			'class': 'btn cbi-button cbi-button-action',
			'href': st.address || '#',
			'target': '_blank',
			'rel': 'noopener',
			'style': 'margin-right:.5rem;margin-bottom:.5rem'
		}, [ _('打开面板') ]));

		ops.push(actionButton(_('卸载容器'), [ 'remove' ], true));

		var opsPanel = E('div', { 'class': 'cbi-section p1-actions' }, [
			E('h3', {}, [ _('操作') ]),
			E('div', {}, ops),
			out
		]);

		poll.add(function() {
			return refresh();
		}, 15);

		return E('div', {}, [
			E('style', {}, [ GRID_CSS ]),
			E('h2', {}, [ _('1Panel') ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('1Panel 以容器方式运行（OpenWrt 没有 systemd，官方安装脚本不可用）。Docker 管理、应用商店、文件（限已挂载目录）、计划任务可用；系统监控与防火墙读的是容器内部，不代表真实路由器。')
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'p1-wrap' }, [ grid ])
			]),

			installPanel || opsPanel
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
