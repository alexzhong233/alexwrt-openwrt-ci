'use strict';
'require view';
'require fs';
'require poll';

/*
 * eMMC 寿命与写入监测 - 详情页
 *
 * 数据来源：/usr/libexec/emmc-health-info（由 rpcd ACL 直接授权执行）。
 * 数据字段定义见 LuCI/luci-app-emmc-health 规范第 4 节；为了兼容脚本实现的
 * 细微差异，这里对挂载点等字段做了别名兼容。
 */

var DATA_SCRIPT = '/usr/libexec/emmc-health-info';
var REFRESH_SEC = 10;

var state = {
	body: null,
	status: null,
	showRaw: false,
	last: {},
	lastRates: {},
	data: null
};

var CSS = [
	'.emmc-dashboard { font-family: inherit; }',
	'.emmc-header { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; margin-bottom: 8px; }',
	'.emmc-header h2 { margin: 0; }',
	'.emmc-header-actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }',
	'.emmc-status { font-size: 12px; opacity: .75; }',
	'.emmc-kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin: 10px 0 16px; }',
	'.emmc-kpi { border: 1px solid rgba(128,128,128,0.35); border-radius: 6px; padding: 12px 14px; background: rgba(128,128,128,0.08); }',
	'.emmc-kpi-title { font-size: 12px; opacity: .75; letter-spacing: .03em; }',
	'.emmc-kpi-value { font-size: 20px; font-weight: 600; margin: 6px 0 4px; word-break: break-word; }',
	'.emmc-kpi-sub { font-size: 12px; opacity: .8; line-height: 1.5; margin-top: 6px; }',
	'.emmc-section { border: 1px solid rgba(128,128,128,0.3); border-radius: 6px; padding: 10px 14px 14px; margin: 0 0 14px; background: rgba(128,128,128,0.05); }',
	'.emmc-section h3 { margin: 4px 0 10px; font-size: 15px; }',
	'.emmc-table-wrap { width: 100%; overflow-x: auto; -webkit-overflow-scrolling: touch; }',
	'.emmc-table { width: 100%; border-collapse: collapse; }',
	'.emmc-table th, .emmc-table td { padding: 6px 8px; border-bottom: 1px solid rgba(128,128,128,0.25); text-align: left; vertical-align: top; }',
	'.emmc-table th { font-size: 12px; opacity: .8; white-space: nowrap; }',
	'.emmc-table td { overflow-wrap: anywhere; word-break: break-word; }',
	'.emmc-col-nowrap { white-space: nowrap; }',
	'.emmc-col-dev { min-width: 140px; }',
	'.emmc-col-usage, .emmc-col-usage .cbi-value-description { min-width: 150px; white-space: nowrap; }',
	'.emmc-col-flags { min-width: 220px; width: 42%; }',
	'.emmc-flag-badge { font-weight: 600; }',
	'.emmc-table .emmc-opts { margin-top: 4px; font-size: 12px; line-height: 1.5; opacity: .8; white-space: normal; word-break: break-word; overflow-wrap: anywhere; }',
	'.emmc-banner { border: 1px solid #fb8c00; border-left-width: 4px; border-radius: 4px; background: rgba(251,140,0,0.12); padding: 10px 14px; margin: 0 0 16px; line-height: 1.6; }',
	'.emmc-bar { height: 6px; width: 100%; background: rgba(128,128,128,0.25); border-radius: 3px; overflow: hidden; margin: 4px 0; }',
	'.emmc-bar span { display: block; height: 100%; }',
	'.emmc-good { color: #43a047; }',
	'.emmc-warn { color: #fb8c00; }',
	'.emmc-bad { color: #e53935; }',
	'.emmc-muted { color: rgba(128,128,128,1); }',
	'.emmc-bar .emmc-good { background: #43a047; color: inherit; }',
	'.emmc-bar .emmc-warn { background: #fb8c00; color: inherit; }',
	'.emmc-bar .emmc-bad { background: #e53935; color: inherit; }',
	'.emmc-raw-head { display: flex; align-items: center; justify-content: space-between; gap: 10px; flex-wrap: wrap; margin-bottom: 8px; }',
	'.emmc-raw { max-height: 320px; overflow: auto; padding: 10px; border-radius: 4px; font-size: 12px; line-height: 1.5; background: rgba(128,128,128,0.12); white-space: pre-wrap; word-break: break-all; margin: 0; }'
].join('\n');

/* fs.exec 在不同 LuCI 版本上返回 stdout 字符串或 { code, stdout, stderr } */
function execStdout(res) {
	if (res == null)
		return '';
	if (typeof res === 'string')
		return res;
	return res.stdout || '';
}

function fetchData() {
	return fs.exec(DATA_SCRIPT).then(function(res) {
		if (res && typeof res === 'object' && res.code && Number(res.code) !== 0)
			throw new Error(res.stderr || ('命令退出码 ' + res.code));

		var data;
		try {
			data = JSON.parse(execStdout(res) || '{}');
		}
		catch (e) {
			throw new Error('无法解析监测数据：' + e.message);
		}

		if (!data || typeof data !== 'object')
			data = { devices: [] };

		state.lastRates = snapshotRates(data);
		state.data = data;
		return data;
	});
}

/* 用相邻两次 write_bytes 差值 / 时间差计算实时写入速率（字节/秒） */
function snapshotRates(data) {
	var now = Date.now();
	var rates = {};
	var devices = (data && data.devices) || [];

	devices.forEach(function(d, i) {
		var key = String(d.device || d.bus_id || i);
		var bytes = Number(d.write_bytes);
		if (!isFinite(bytes) || bytes < 0)
			bytes = null;

		var prev = state.last[key];
		if (bytes !== null && prev && prev.bytes !== null) {
			var delta = bytes - prev.bytes;
			var secs = (now - prev.ts) / 1000;
			if (delta >= 0 && secs > 0)
				rates[key] = delta / secs;
		}

		state.last[key] = { bytes: bytes, ts: now };
	});

	return rates;
}

function val(v) {
	return (v === undefined || v === null || v === '') ? '—' : String(v);
}

function fmtBytes(v) {
	var b = Number(v);
	if (!isFinite(b) || b < 0)
		return '—';
	if (b >= 1024 * 1024 * 1024 * 1024)
		return (b / (1024 * 1024 * 1024 * 1024)).toFixed(2) + ' TiB';
	if (b >= 1024 * 1024 * 1024)
		return (b / (1024 * 1024 * 1024)).toFixed(2) + ' GiB';
	if (b >= 1024 * 1024)
		return (b / (1024 * 1024)).toFixed(1) + ' MiB';
	if (b >= 1024)
		return (b / 1024).toFixed(1) + ' KiB';
	return b.toFixed(0) + ' B';
}

function fmtRate(bps) {
	if (bps == null || !isFinite(bps) || bps < 0)
		return '采样中…';
	if (bps >= 1024 * 1024)
		return (bps / (1024 * 1024)).toFixed(2) + ' MB/s';
	if (bps >= 1024)
		return (bps / 1024).toFixed(1) + ' KB/s';
	return bps.toFixed(0) + ' B/s';
}

function lifeInfo(v) {
	var n = parseInt(v, 16);
	if (!isFinite(n) || n < 1)
		return { n: 0, text: '未知', cls: 'emmc-muted', raw: val(v) };
	if (n >= 0x0b)
		return { n: n, text: '>100%（超出预估寿命）', pct: 100, cls: 'emmc-bad', raw: val(v) };
	return {
		n: n,
		text: ((n - 1) * 10) + '–' + (n * 10) + '%',
		pct: n * 10,
		cls: n >= 9 ? 'emmc-warn' : 'emmc-good',
		raw: val(v)
	};
}

function preEolInfo(v) {
	var n = parseInt(val(v), 16);
	if (n === 1)
		return { n: 1, text: '正常（备用块 <80%）', cls: 'emmc-good', raw: val(v) };
	if (n === 2)
		return { n: 2, text: '警告（备用块 80%–90%）', cls: 'emmc-warn', raw: val(v) };
	if (n === 3)
		return { n: 3, text: '严重（备用块 >90%）', cls: 'emmc-bad', raw: val(v) };
	return { n: 0, text: '未知（' + val(v) + '）', cls: 'emmc-muted', raw: val(v) };
}

function bar(pct, cls) {
	var p = Math.max(0, Math.min(100, Number(pct) || 0));
	return E('div', { 'class': 'emmc-bar' }, [
		E('span', { 'class': cls || 'emmc-good', 'style': 'width:' + p + '%' })
	]);
}

function kpi(title, value, sub, cls, pct) {
	var children = [
		E('div', { 'class': 'emmc-kpi-title' }, [ title ]),
		E('div', { 'class': 'emmc-kpi-value ' + (cls || '') }, [ value ])
	];
	if (pct != null)
		children.push(bar(pct, cls));
	children.push(E('div', { 'class': 'emmc-kpi-sub' }, [ sub ]));
	return E('div', { 'class': 'emmc-kpi' }, children);
}

function totalRate(devices) {
	var sum = 0;
	var has = false;
	devices.forEach(function(d, i) {
		var key = String(d.device || d.bus_id || i);
		var r = state.lastRates && state.lastRates[key];
		if (typeof r === 'number' && isFinite(r)) {
			sum += r;
			has = true;
		}
	});
	return has ? sum : null;
}

function noatimeStatus(devices) {
	var total = 0;
	var on = 0;
	var rel = 0;
	devices.forEach(function(d) {
		((d && d.mounts) || []).forEach(function(m) {
			total++;
			var opts = String(m.options || m.opts || '');
			if (Number(m.noatime) === 1 || /(^|,|\s)noatime(,|\s|$)/.test(opts))
				on++;
			else if (/(^|,|\s)relatime(,|\s|$)/.test(opts))
				rel++;
		});
	});
	if (!total)
		return '无已挂载分区';
	if (on === total)
		return '已启用';
	if (on > 0)
		return '部分启用（' + on + '/' + total + '）';
	if (rel > 0)
		return '未启用（relatime）';
	return '未启用';
}

function renderKpis(devices) {
	var pre = { n: -1, text: '—', cls: 'emmc-muted', raw: '—' };
	var a = { n: -1, text: '—', cls: 'emmc-muted', raw: '—' };
	var b = { n: -1, text: '—', cls: 'emmc-muted', raw: '—' };
	var totalWrite = 0;

	devices.forEach(function(d) {
		var p = preEolInfo(d.pre_eol);
		var la = lifeInfo(d.life_a);
		var lb = lifeInfo(d.life_b);
		if (p.n > pre.n) pre = p;
		if (la.n > a.n) a = la;
		if (lb.n > b.n) b = lb;
		var w = Number(d.write_bytes);
		if (isFinite(w) && w > 0)
			totalWrite += w;
	});

	return E('div', { 'class': 'emmc-kpi-grid' }, [
		kpi('Pre-EOL 备用块状态', pre.text,
			'原始值 ' + pre.raw + ' · 共 ' + devices.length + ' 块设备', pre.cls),
		kpi('Type A (SLC) 寿命消耗', a.text,
			'原始值 ' + a.raw + ' · 增强区 / SLC', a.cls, a.pct),
		kpi('Type B (MLC/TLC) 寿命消耗', b.text,
			'原始值 ' + b.raw + ' · 主存储区', b.cls, b.pct),
		kpi('本次开机累计写入量', fmtBytes(totalWrite),
			'实时写入 ' + fmtRate(totalRate(devices)) + ' · 挂载 noatime：' + noatimeStatus(devices))
	]);
}

function renderBanner(devices) {
	var reasons = [];
	devices.forEach(function(d) {
		var name = val(d.device);
		if (parseInt(d.life_a, 16) >= 0x0b)
			reasons.push(name + ' Type A 寿命超出预估（' + val(d.life_a) + '）');
		if (parseInt(d.life_b, 16) >= 0x0b)
			reasons.push(name + ' Type B 寿命超出预估（' + val(d.life_b) + '）');
		var n = parseInt(val(d.pre_eol), 16);
		if (n === 2 || n === 3)
			reasons.push(name + ' Pre-EOL 状态 ' + val(d.pre_eol));
	});

	return E('div', { 'class': 'emmc-banner' }, [
		E('strong', { 'class': 'emmc-bad' }, [ '寿命预警：' ]),
		'检测到 ' + reasons.join('、') + '。建议：启用挂载 noatime 以减少元数据写入；限制 Docker 日志轮转（设置日志大小上限与保留份数）；将高写入数据（下载、数据库、日志）迁移至外接 SSD。'
	]);
}

function row(label, value, hint) {
	var cell = E('td', { 'class': 'td left' }, [ value ]);
	if (hint)
		cell.appendChild(E('div', { 'class': 'cbi-value-description' }, [ hint ]));
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '28%' }, [ label ]),
		cell
	]);
}

function renderDeviceSection(d) {
	return E('div', { 'class': 'emmc-section' }, [
		E('h3', {}, [ val(d.device) + ' · ' + val(d.vendor || 'Unknown') ]),
		E('div', { 'class': 'emmc-table-wrap' }, [
			E('table', { 'class': 'table emmc-table' }, [
				row('设备节点', E('code', {}, [ '/dev/' + val(d.device) ]), 'MMC bus: ' + val(d.bus_id)),
				row('型号', val(d.name)),
				row('厂商', val(d.vendor || 'Unknown')),
				row('固件 / 硬件版本', val(d.fwrev) + ' / ' + val(d.hwrev)),
				row('生产日期', val(d.date)),
				row('序列号', val(d.serial)),
				row('Manfid / OEM ID', val(d.manfid) + ' / ' + val(d.oemid)),
				row('总容量', fmtBytes(d.size_bytes), 'EXT_CSD rev: ' + val(d.ext_csd_rev)),
				row('Cache', val(d.cache_size), 'Cache ctrl: ' + val(d.cache_ctrl)),
				row('TRIM', val(d.trim_mult)),
				row('BKOPS', val(d.bkops_support), 'BKOPS EN: ' + val(d.bkops_en)),
				row('Boot / RPMB', 'Boot: ' + val(d.boot_size_multi) + ' · RPMB: ' + val(d.rpmb_size_mult)),
				row('读取', fmtBytes(d.read_bytes), val(d.read_ios) + ' 次 I/O'),
				row('写入', fmtBytes(d.write_bytes), val(d.write_ios) + ' 次 I/O'),
				row('Discard I/O', val(d.discard_ios))
			])
		])
	]);
}

function firstVal(obj, keys) {
	for (var i = 0; i < keys.length; i++) {
		var v = obj && obj[keys[i]];
		if (v !== undefined && v !== null && v !== '')
			return String(v);
	}
	return '';
}

function renderMountsSection(devices) {
	var mounts = [];
	devices.forEach(function(d) {
		((d && d.mounts) || []).forEach(function(m) {
			mounts.push(m);
		});
	});

	var head = E('tr', {}, [
		E('th', {}, [ '挂载点' ]),
		E('th', {}, [ '设备' ]),
		E('th', {}, [ '文件系统' ]),
		E('th', {}, [ '空间使用' ]),
		E('th', {}, [ '标记' ])
	]);

	if (!mounts.length) {
		return E('div', { 'class': 'emmc-section' }, [
			E('h3', {}, [ '已挂载 eMMC 分区' ]),
			E('div', { 'class': 'cbi-value-description' }, [ '未检测到 eMMC 挂载点。' ])
		]);
	}

	var body = mounts.map(function(m) {
		var mp = firstVal(m, [ 'mountpoint', 'mount_point', 'mp', 'target', 'path' ]);
		var dev = firstVal(m, [ 'device', 'dev', 'source' ]);
		var fstype = firstVal(m, [ 'fstype', 'fs', 'type' ]);
		var opts = firstVal(m, [ 'options', 'opts' ]);
		var total = Number(m.total_kb);
		var used = Number(m.used_kb);
		var avail = Number(m.avail_kb);
		var pct = Number(m.use_pct);
		if (!isFinite(pct) || pct < 0) {
			if (isFinite(total) && total > 0 && isFinite(used))
				pct = Math.round(used / total * 100);
			else if (isFinite(total) && total > 0 && isFinite(avail))
				pct = Math.round((total - avail) / total * 100);
			else
				pct = 0;
		}
		var cls = pct >= 90 ? 'emmc-bad' : (pct >= 80 ? 'emmc-warn' : 'emmc-good');
		var isNoatime = Number(m.noatime) === 1 || /(^|,|\s)noatime(,|\s|$)/.test(opts);
		var flag = isNoatime
			? 'noatime'
			: (/(^|,|\s)relatime(,|\s|$)/.test(opts) ? 'relatime' : '默认 (atime)');
		var flagCls = isNoatime ? 'emmc-flag-badge emmc-good' : 'emmc-flag-badge emmc-warn';
		var optsDisplay = opts ? opts.replace(/,\s*/g, ', ') : '';

		return E('tr', {}, [
			E('td', { 'class': 'emmc-col-nowrap' }, [ E('code', {}, [ mp || '—' ]) ]),
			E('td', { 'class': 'emmc-col-dev' }, [ E('code', {}, [ dev || '—' ]) ]),
			E('td', { 'class': 'emmc-col-nowrap' }, [ fstype || '—' ]),
			E('td', { 'class': 'emmc-col-usage' }, [
				bar(pct, cls),
				E('span', { 'class': cls }, [ pct + '%' ]),
				E('div', { 'class': 'cbi-value-description' }, [
					fmtBytes(isFinite(used) ? used * 1024 : null) + ' / ' +
					fmtBytes(isFinite(total) ? total * 1024 : null)
				])
			]),
			E('td', { 'class': 'emmc-col-flags' }, [
				E('span', { 'class': flagCls }, [ flag ]),
				optsDisplay ? E('div', { 'class': 'emmc-opts', 'title': opts }, [ optsDisplay ]) : ''
			])
		]);
	});

	return E('div', { 'class': 'emmc-section' }, [
		E('h3', {}, [ '已挂载 eMMC 分区' ]),
		E('div', { 'class': 'emmc-table-wrap' }, [
			E('table', { 'class': 'table emmc-table emmc-mounts-table' }, [ head ].concat(body))
		])
	]);
}

function renderRawSection(devices) {
	var parts = [];
	devices.forEach(function(d) {
		var raw = d && d.raw_extcsd;
		if (raw)
			parts.push('=== /dev/' + val(d.device) + ' ===\n' + raw);
	});

	var raw = E('pre', {
		'class': 'emmc-raw',
		'style': state.showRaw ? '' : 'display:none'
	}, [ parts.length ? parts.join('\n\n') : '（无可用 EXT_CSD 原始输出）' ]);

	var label = E('span', {}, [ state.showRaw ? '隐藏原始输出' : '显示原始输出' ]);
	var toggle = E('button', {
		'class': 'btn cbi-button',
		'click': function() {
			state.showRaw = !state.showRaw;
			raw.style.display = state.showRaw ? '' : 'none';
			label.textContent = state.showRaw ? '隐藏原始输出' : '显示原始输出';
		}
	}, [ label ]);

	return E('div', { 'class': 'emmc-section' }, [
		E('div', { 'class': 'emmc-raw-head' }, [
			E('strong', {}, [ 'EXT_CSD 关键寄存器原始输出' ]),
			toggle
		]),
		raw
	]);
}

function buildBody(data) {
	var devices = (data && data.devices) || [];
	var nodes = [];

	if (data && data.error) {
		nodes.push(E('div', { 'class': 'emmc-banner emmc-bad' }, [
			'数据读取失败：' + data.error
		]));
	}

	if (!devices.length) {
		nodes.push(E('div', { 'class': 'emmc-section' }, [
			'未检测到 eMMC 设备。'
		]));
		return nodes;
	}

	nodes.push(renderKpis(devices));

	var hasWarning = devices.some(function(d) {
		var pre = parseInt(val(d.pre_eol), 16);
		return parseInt(d.life_a, 16) >= 0x0b || parseInt(d.life_b, 16) >= 0x0b || pre === 2 || pre === 3;
	});
	if (hasWarning)
		nodes.push(renderBanner(devices));

	devices.forEach(function(d) {
		nodes.push(renderDeviceSection(d));
	});

	nodes.push(renderMountsSection(devices));
	nodes.push(renderRawSection(devices));

	return nodes;
}

function renderInto(data) {
	if (!state.body)
		return;

	while (state.body.firstChild)
		state.body.removeChild(state.body.firstChild);

	buildBody(data).forEach(function(node) {
		if (node)
			state.body.appendChild(node);
	});
}

function refresh() {
	return fetchData().then(function(data) {
		renderInto(data);
		if (state.status)
			state.status.textContent = '最近更新：' + new Date().toLocaleTimeString();
	}).catch(function(e) {
		if (state.status)
			state.status.textContent = '刷新失败：' + ((e && e.message) ? e.message : String(e));
	});
}

return view.extend({
	load: function() {
		return fetchData().catch(function(e) {
			return { devices: [], error: (e && e.message) ? e.message : String(e) };
		});
	},

	render: function(data) {
		data = data || { devices: [] };
		state.data = data;
		if (!state.lastRates)
			state.lastRates = snapshotRates(data);

		var refreshBtn = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': function() { refresh(); }
		}, [ '立即刷新' ]);

		var root = E('div', { 'class': 'cbi-map emmc-dashboard' }, [
			E('style', { 'type': 'text/css' }, [ CSS ]),
			E('div', { 'class': 'emmc-header' }, [
				E('h2', {}, [ 'eMMC 寿命与写入监测' ]),
				E('div', { 'class': 'emmc-header-actions' }, [
					state.status = E('span', { 'class': 'emmc-status' }, [ '最近更新：' + new Date().toLocaleTimeString() ]),
					refreshBtn
				])
			]),
			state.body = E('div', { 'class': 'emmc-body' })
		]);

		renderInto(data);

		/* 视图可能被重复 render，先移除旧的 poller 再注册每 10 秒轮询 */
		poll.remove(refresh);
		poll.add(refresh, REFRESH_SEC);

		return root;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
