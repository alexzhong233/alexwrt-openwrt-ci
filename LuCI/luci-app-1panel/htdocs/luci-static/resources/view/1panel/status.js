'use strict';
'require view';
'require fs';
'require ui';
'require poll';

var TOOL = '/usr/libexec/1panel-ctl';

function call(args) {
	return fs.exec(TOOL, args).then(function(res) {
		var text = ((res && res.stdout) || '') + ((res && res.stderr) || '');

		return { code: res ? res.code : 1, text: String(text).replace(/\s+$/, '') };
	}).catch(function(err) {
		return { code: 1, text: '执行失败：' + (err && err.message ? err.message : err) };
	});
}

function parseKV(text) {
	var out = {};

	(text || '').split('\n').forEach(function(line) {
		var idx = line.indexOf('=');

		if (idx > 0)
			out[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
	});

	return out;
}

function flag(v) {
	return String(v) === '1';
}

function mb(kb) {
	var n = parseInt(kb, 10) || 0;

	return n >= 1048576 ? (n / 1048576).toFixed(1) + ' GB' : Math.round(n / 1024) + ' MB';
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

/* 任务阶段：downloading:v2.4.2 / installing:... / done:... / error:... */
function parseTask(s) {
	var raw = String(s || 'idle');
	var i = raw.indexOf(':');

	return i > 0
		? { phase: raw.substring(0, i), detail: raw.substring(i + 1) }
		: { phase: raw, detail: '' };
}

var PHASE_TEXT = {
	downloading: _('下载安装包'),
	extracting: _('解包'),
	installing: _('安装文件并注册服务'),
	starting: _('等待服务就绪'),
	updating: _('升级中'),
	done: _('完成'),
	error: _('失败'),
	idle: _('空闲')
};

function busy(phase) {
	return phase === 'downloading' || phase === 'extracting' || phase === 'installing'
		|| phase === 'starting' || phase === 'updating';
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
	'.p1-form input { width: 100%; box-sizing: border-box; }',
	'.p1-task { margin-top: 1rem; padding: .6rem .8rem; border-left: 3px solid #3b82f6;',
	'  background: rgba(59,130,246,.08); }',
	'.p1-task.err { border-left-color: #dc2626; background: rgba(220,38,38,.08); }',
	'.p1-task.ok { border-left-color: #16a34a; background: rgba(22,163,74,.08); }',
	'.p1-warn { color: #d97706; }',
	'.p1-up { color: #dc2626; font-weight: bold; }'
].join('\n');

return view.extend({
	load: function() {
		return Promise.all([
			call([ 'status' ]),
			call([ 'latest' ])
		]);
	},

	buildRows: function(st, latest) {
		var installed = flag(st.installed);
		var running = flag(st.running);
		var cur = st.version || '';
		var newv = latest || st.latest || '';
		var t = parseTask(st.task);

		function row(label, value) {
			return [
				E('div', { 'class': 'p1-c' }, [ label ]),
				E('div', { 'class': 'p1-c' }, Array.isArray(value) ? value : [ value ])
			];
		}

		var rows = [];

		rows = rows.concat(row(_('状态'), !installed
			? badge(false, '', _('未安装'))
			: badge(running, _('运行中'), _('已停止'))));

		if (installed) {
			var verCell = [ E('code', {}, [ cur || '—' ]) ];

			if (newv && cur && newv !== cur)
				verCell.push(E('span', { 'class': 'p1-up', 'style': 'margin-left:.6rem' },
					[ _('有新版本 %s').format(newv) ]));
			else if (newv && cur && newv === cur)
				verCell.push(muted(' ' + _('（已是最新）')));

			rows = rows.concat(row(_('版本'), verCell));
			rows = rows.concat(row(_('核心里程'), running
				? E('code', {}, [ 'PID ' + (st.pid || '?') + (flag(st.listening) ? _('，端口已监听') : _('，端口未监听')) ])
				: muted(_('未运行'))));
		}

		rows = rows.concat(row(_('访问地址'), installed ? link(st.address)
			: muted(_('安装后可用'))));

		/* 刷机后：二进制没了，/mnt 里的数据库还在。重装会沿用账号与设置。 */
		if (!installed && flag(st.datakept))
			rows = rows.concat(row(_('已有数据'), E('span', { 'class': 'p1-warn' }, [
				_('检测到 %s，重装会保留账号、密码与入口').format(st.rundir || '')
			])));
		rows = rows.concat(row(_('监听端口'), st.port || '—'));
		rows = rows.concat(row(_('登录账号'), st.username || '—'));
		rows = rows.concat(row(_('入口路径'), st.entrance
			? E('code', {}, [ st.entrance ])
			: muted(_('未设置'))));
		rows = rows.concat(row(_('数据目录'), [
			E('code', {}, [ st.datadir || '—' ]),
			installed && st.datasize
				? muted(' ' + _('（当前 %s）').format(mb(st.datasize)))
				: ''
		]));
		rows = rows.concat(row(_('数据盘剩余'), mb(st.data_free_kb)));
		rows = rows.concat(row(_('overlay 剩余'), [
			mb(st.overlay_free_kb),
			!installed && parseInt(st.overlay_free_kb, 10) < 204800
				? E('span', { 'class': 'p1-warn' }, [ ' ' + _('（不足 200MB，装不下 152MB 的二进制）') ])
				: ''
		]));

		if (busy(t.phase) || t.phase === 'error' || t.phase === 'done') {
			var cls = 'p1-task' + (t.phase === 'error' ? ' err' : (t.phase === 'done' ? ' ok' : ''));

			rows.push(E('div', { 'class': 'p1-c', 'style': 'grid-column:1 / -1; padding:0; border:0' }, [
				E('div', { 'class': cls }, [
					E('strong', {}, [ PHASE_TEXT[t.phase] || t.phase ]),
					t.detail ? E('span', {}, [ ' ' + t.detail ]) : '',
					t.phase === 'error'
						? E('div', { 'style': 'margin-top:.4rem' }, [
							muted(_('看下「查看日志」里的输出，或 /var/run/1panel-task/log。'))
						])
						: ''
				])
			]));
		}

		return rows;
	},

	render: function(results) {
		var self = this;
		var st = parseKV(results[0] ? results[0].text : '');
		var latest = parseKV(results[1] ? results[1].text : '').latest || st.latest || '';

		var grid = E('div', { 'class': 'p1-grid' });
		var out = E('pre', {
			'id': 'p1-out',
			'style': 'max-height:20rem;overflow:auto;white-space:pre-wrap;word-break:break-all;margin:0'
		}, [ _('（还没有执行任何操作）') ]);

		function setOut(text) {
			out.textContent = text || _('（无输出）');
		}

		function fill(fresh, lv) {
			while (grid.firstChild)
				grid.removeChild(grid.firstChild);

			self.buildRows(fresh, lv).forEach(function(node) {
				grid.appendChild(node);
			});
		}

		fill(st, latest);

		function refresh() {
			return call([ 'status' ]).then(function(res) {
				var fresh = parseKV(res.text);

				st = fresh;
				/* status 里的 latest 来自缓存，「检查更新」跑完这里就能拿到新值。 */
				latest = fresh.latest || latest;
				fill(fresh, latest);

				/* 安装完成或卸载后，表单/按钮要互换，整页重绘最省事。 */
				if (flag(fresh.installed) !== installed)
					window.setTimeout(function() { location.reload(); }, 1500);

				return fresh;
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

		function button(label, args, opts) {
			opts = opts || {};

			return E('button', {
				'class': 'btn cbi-button' + (opts.primary ? ' cbi-button-apply' : '') +
					(opts.danger ? ' cbi-button-reset' : ''),
				'disabled': opts.disabled ? 'disabled' : null,
				'click': function(ev) {
					ev.preventDefault();

					if (opts.confirm && !window.confirm(opts.confirm))
						return;

					return run(args, label, opts.reload);
				}
			}, [ label ]);
		}

		var installed = flag(st.installed);
		var running = flag(st.running);
		var t = parseTask(st.task);
		var inFlight = busy(t.phase);
		var canUpdate = installed && latest && st.version && latest !== st.version;

		/* ---- 未安装：安装表单 ---- */
		var installPanel = null;

		if (!installed) {
			function field(label, value, type, placeholder) {
				var input = E('input', {
					'type': type || 'text',
					'class': 'cbi-input-text',
					'placeholder': placeholder || '',
					'value': value || ''
				});

				return { input: input, nodes: [ E('label', {}, [ label ]), input ] };
			}

			var fPort = field(_('监听端口'), st.port || '10086');
			var fUser = field(_('登录账号'), st.username || '1panel');
			var fPass = field(_('登录密码'), '', 'password', _('8 位以上，别用 password'));
			var fEnt = field(_('入口路径'), '', 'text', _('例如 panel-8x3k，别用 entrance'));
			var fDir = field(_('数据目录'), st.datadir || '/mnt/sda1/Configs/1Panel');

			var installBtn = E('button', {
				'class': 'btn cbi-button cbi-button-apply',
				'disabled': inFlight ? 'disabled' : null
			}, [ inFlight ? _('安装进行中…') : _('开始安装') ]);

			installBtn.addEventListener('click', function(ev) {
				ev.preventDefault();

				/* 重装时留空是合法的：安装脚本会沿用数据库里的旧值。 */
				var kept = flag(st.datakept);

				if (!kept && (!fPass.input.value || fPass.input.value.length < 8)) {
					ui.addNotification(null, E('p', {}, [ _('密码至少 8 位') ]), 'warning');
					return;
				}

				if (!kept && !fEnt.input.value) {
					ui.addNotification(null, E('p', {}, [ _('入口路径不能为空，随便起一个不容易猜的名字') ]), 'warning');
					return;
				}

				if (fDir.input.value.indexOf('/mnt/') !== 0) {
					ui.addNotification(null, E('p', {}, [
						_('数据目录必须在 /mnt 下：面板的数据库和应用都写在这里，放 overlay 会写满 flash，刷机也会丢。')
					]), 'warning');
					return;
				}

				/* 安装要 2-3 分钟，先禁用按钮，避免重复提交。 */
				installBtn.disabled = true;
				installBtn.textContent = _('安装进行中…');

				return run([ 'install', fPort.input.value, fUser.input.value,
					fPass.input.value, fEnt.input.value, fDir.input.value ],
					_('安装'), false);
			});

			installPanel = E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('安装 1Panel') ]),
				E('div', { 'class': 'cbi-map-descr' }, [
					_('从官方源拉取最新版，用官方 install.sh 安装（OpenWrt 上用 procd 托管）。'),
					E('br'),
					_('端口、账号、密码、入口路径都可在这里指定；数据目录必须在 /mnt 下，面板的数据库、日志、备份都写在那里。'),
					E('br'),
					_('两个二进制约 152MB 会写到 overlay，装完刷新即用。'),
					flag(st.datakept)
						? E('div', { 'class': 'p1-warn', 'style': 'margin-top:.4rem' }, [
							_('检测到已有数据（%s）：账号、密码、入口路径可以留空，将沿用原来的值。').format(st.rundir || '')
						])
						: ''
				]),
				E('div', { 'class': 'p1-form', 'style': 'margin-top:1rem' },
					[].concat(fPort.nodes, fUser.nodes, fPass.nodes, fEnt.nodes, fDir.nodes)),
				E('div', { 'style': 'margin-top:1rem' }, [ installBtn ]),
				out
			]);
		}

		/* ---- 已安装：操作按钮 ---- */
		var opsPanel = null;

		if (installed) {
			var ops = [];

			if (canUpdate)
				ops.push(button(_('更新到 %s').format(latest), [ 'update' ],
					{ primary: true, disabled: inFlight }));

			ops.push(running
				? button(_('停止'), [ 'stop' ], { disabled: inFlight })
				: button(_('启动'), [ 'start' ], { primary: true, disabled: inFlight }));

			ops.push(button(_('重启'), [ 'restart' ], { disabled: inFlight }));
			ops.push(button(_('检查更新'), [ 'latest' ]));
			ops.push(button(_('查看日志'), [ 'logs' ]));

			ops.push(E('a', {
				'class': 'btn cbi-button cbi-button-action',
				'href': st.address || '#',
				'target': '_blank',
				'rel': 'noopener',
				'style': 'margin-right:.5rem;margin-bottom:.5rem'
			}, [ _('打开面板') ]));

			ops.push(button(_('卸载'), [ 'remove' ], {
				danger: true,
				disabled: inFlight,
				confirm: _('卸载会删除程序和 procd 服务，数据目录保留。继续？')
			}));

			ops.push(button(_('卸载并删除数据'), [ 'remove', 'purge' ], {
				danger: true,
				disabled: inFlight,
				confirm: _('这会连同 %s 里的数据库、日志、备份一起删掉，不可恢复。继续？').format(st.datadir)
			}));

			opsPanel = E('div', { 'class': 'cbi-section p1-actions' }, [
				E('h3', {}, [ _('操作') ]),
				E('div', {}, ops),
				out
			]);
		}

		/* 后台任务在跑时也要看到进度，8 秒一轮；status 不联网，只读本地状态。 */
		poll.add(function() {
			return refresh();
		}, 8);

		return E('div', {}, [
			E('style', {}, [ GRID_CSS ]),
			E('h2', {}, [ _('1Panel') ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('裸机安装的 1Panel v2，用 procd 托管 1panel-core 与 1panel-agent。'),
				E('br'),
				_('升级走官方流程（1pctl update），只替换二进制；刷机后程序会丢、数据在 /mnt 不受影响，重装时脚本识别到已有数据库会保留账号。')
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
