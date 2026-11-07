'use strict';
'require view';
'require fs';
'require ui';

/*
 * nss-wifi-drv 的状态与统计页面。
 *
 * 数据来源（都由驱动直接暴露，不是我们的估算）：
 *   /sys/bus/platform/devices/39000000.nss/state     一行 key=value 汇总
 *   /sys/kernel/debug/39000000.nss/wifili_rx         每个 vdev 的收发计数（含字节）
 *   /sys/kernel/debug/39000000.nss/flows             已下发给固件的流转发计数
 *   /sys/kernel/debug/39000000.nss/log               NSS 固件日志
 *   /sys/module/ath11k/parameters/nss_offload        Y/N，Wi-Fi 是否切到 NSS
 *   /sys/module/nss_wifi_drv/parameters/{wlan,firmware}
 *
 * debugfs 由驱动在 probe 时创建（debugfs_create_dir(dev_name(dev))），设备名
 * 来自 DTS 里的 39000000.nss。换板子的话这个路径要跟着改。
 */

var BUS = '/sys/bus/platform/devices/39000000.nss';
var DBG = '/sys/kernel/debug/39000000.nss';

function cat(path) {
	return fs.exec('/bin/cat', [ path ]).then(function(r) {
		return (r && r.code === 0) ? String(r.stdout || '') : '';
	}).catch(function() { return ''; });
}

function tailFile(path, lines) {
	return fs.exec('/bin/sh', [ '-c', 'tail -n "$1" "$2"', 'sh', String(lines), path ])
		.then(function(r) {
			return (r && r.code === 0) ? String(r.stdout || '') : '';
		}).catch(function() { return ''; });
}

function parseKv(text) {
	var out = {};
	var first = (text || '').trim().split('\n')[0] || '';
	first.trim().split(/\s+/).forEach(function(tok) {
		var i = tok.indexOf('=');
		if (i > 0)
			out[tok.slice(0, i)] = tok.slice(i + 1);
	});
	return out;
}

function parseVdevs(text) {
	var list = [], cur = null;

	(text || '').split('\n').forEach(function(line) {
		var t = line.trim();
		if (t === '')
			return;

		var m = t.match(/^vdev if (\d+) reports (\d+)$/);
		if (m) {
			cur = { ifnum: +m[1], reports: +m[2] };
			list.push(cur);
			return;
		}
		if (cur === null)
			return;

		var kv = {};
		t.replace(/([a-z_]+)\s+(\d+)/g, function(_, k, v) { kv[k] = +v; return ''; });

		if (t.indexOf('rx enqueue') === 0) {
			cur.rx = kv.enqueue || 0;
			cur.rx_fail = kv.fail || 0;
			cur.except = kv.except || 0;
			cur.bytes = kv.bytes || 0;
			cur.mcast = kv.mcast || 0;
		}
		else if (t.indexOf('rx decrypt_err') === 0) {
			cur.decrypt_err = kv.decrypt_err || 0;
			cur.mic_err = kv.mic_err || 0;
		}
		else if (t.indexOf('tx rcvd') === 0) {
			cur.tx = kv.rcvd || 0;
			cur.hw_ring_full = kv.hw_ring_full || 0;
			cur.dropped = kv.dropped || 0;
		}
	});

	return list;
}

function parseFlows(text) {
	var out = { bound: 0, pushed: 0, nodes: [] };

	(text || '').split('\n').forEach(function(line) {
		var t = line.trim();

		var m = t.match(/^bound (\d+) pushed (\d+)/);
		if (m) {
			out.bound = +m[1];
			out.pushed = +m[2];
			return;
		}

		m = t.match(/^node (\S+) rx (\d+) tx (\d+) drop (\S+)/);
		if (m)
			out.nodes.push({ name: m[1], rx: +m[2], tx: +m[3], drop: m[4] });
	});

	return out;
}

function fmtBytes(n) {
	var v = Number(n) || 0;
	var unit = [ 'B', 'KB', 'MB', 'GB', 'TB' ], i = 0;

	while (v >= 1024 && i < unit.length - 1) {
		v /= 1024;
		i++;
	}

	return (i === 0 ? String(v) : v.toFixed(2)) + ' ' + unit[i];
}

function fmtNum(n) {
	return (Number(n) || 0).toLocaleString();
}

function wlanText(v) {
	var n = parseInt(v, 10) || 0;
	var parts = [];

	if (n & 1)
		parts.push('内置 AHB');
	if (n & 2)
		parts.push('外挂 PCIe');

	if (parts.length === 0)
		return '无（Wi-Fi 未走 NSS）';

	return parts.join(' + ') + '（掩码 ' + n + '）';
}

return view.extend({
	load: function() {
		return Promise.all([
			cat(BUS + '/state'),
			cat(DBG + '/wifili_rx'),
			cat(DBG + '/flows'),
			tailFile(DBG + '/log', 30),
			cat('/sys/module/ath11k/parameters/nss_offload'),
			cat('/sys/module/nss_wifi_drv/parameters/wlan'),
			cat('/sys/module/nss_wifi_drv/parameters/firmware')
		]);
	},

	render: function(data) {
		var stateRaw = data[0], vdevRaw = data[1], flowRaw = data[2], logRaw = data[3];
		var offload = (data[4] || '').trim();
		var wlanParm = (data[5] || '').trim();
		var firmware = (data[6] || '').trim();

		var st = parseKv(stateRaw);
		var vdevs = parseVdevs(vdevRaw);
		var flows = parseFlows(flowRaw);
		var log = (logRaw || '').trim();

		var ready = (st.ready === '1');
		var running = (st.running === '1');
		var peers = Number(st.peers || 0);
		var nvdev = Number(st.vdevs || 0);

		var dot = function(ok, text) {
			return E('span', {
				'style': 'color:' + (ok ? '#4caf50' : '#f44336') + ';font-weight:bold'
			}, [ '● ' + text ]);
		};

		var row = function(label, value, hint) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '22%' }, [ label ]),
				E('td', { 'class': 'td left' }, [
					value,
					hint ? E('div', { 'class': 'cbi-value-description' }, [ hint ]) : ''
				])
			]);
		};

		var th = function(text) {
			return E('th', { 'class': 'th' }, [ text ]);
		};

		var td = function(content, align) {
			return E('td', { 'class': 'td ' + (align || 'left') }, [ content ]);
		};

		/* ---- 概览 ---- */
		var overview = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ 'NSS 数据平面' ]),
			E('table', { 'class': 'table' }, [
				row('加速状态', ready
					? dot(true, '已就绪（ready=1）')
					: (running
						? dot(false, '核心运行但数据平面未就绪（ready 不是 1）')
						: dot(false, '未启动（running 不是 1）')),
					'取自 /sys/bus/platform/devices/39000000.nss/state'),
				row('Wi-Fi 卸载', offload === 'Y'
					? dot(true, 'ath11k 已切到 NSS（nss_offload=Y）')
					: dot(false, 'ath11k 走内核转发（nss_offload=' + (offload || '未知') + '）'),
					'N/Y 由 /sys/module/ath11k/parameters/nss_offload 决定'),
				row('卸载总线', E('code', {}, [ wlanText(wlanParm || st.wlan) ]),
					'掩码 1=内置 AHB，2=外挂 PCIe，3=两路都卸载'),
				row('NSS 核心', E('code', {}, [
					(st.started || '?') + ' / ' + (st.expected || '?') + ' 已启动'
				]), 'started 对 expected，低于说明有核心没起来'),
				row('虚拟接口', E('code', {}, [ String(nvdev) + ' 个 vdev' ]),
					'每个 SSID 一个 vdev，全部由 NSS 收发'),
				row('硬件客户端', E('code', {}, [ String(peers) + ' 台' ]),
					'挂在 NSS 硬件转发表上的 WiFi 客户端数量（peers）'),
				row('固件线', E('code', {}, [ firmware || (st.firmware || '未知') ]),
					'12.5 为默认；跑 802.11s mesh 才需要 11.4'),
				row('Ring 状态', (st.rings_ready === '1')
					? dot(true, 'rings_ready=1')
					: dot(false, 'rings_ready 不是 1，NSS 会拒绝启动'),
					'环形缓冲区交接完成才能 boot 核心')
			])
		]);

		/* ---- vdev 统计 ---- */
		var vdevRows = [];

		if (vdevs.length === 0) {
			vdevRows.push(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '7' }, [
					stateRaw === ''
						? '读不到 wifili_rx：NSS 可能没启动，或 debugfs 未挂载（mount -t debugfs none /sys/kernel/debug）'
						: 'NSS 还没有上报过任何 vdev'
				])
			]));
		}
		else {
			vdevs.forEach(function(v) {
				vdevRows.push(E('tr', { 'class': 'tr' }, [
					td(E('code', {}, [ String(v.ifnum) ]), 'center'),
					td(fmtNum(v.rx), 'right'),
					td(fmtBytes(v.bytes), 'right'),
					td(fmtNum(v.tx), 'right'),
					td(String(v.except || 0), 'right'),
					td(String(v.dropped || 0), 'right'),
					td(String(v.hw_ring_full || 0), 'right')
				]));
			});
		}

		var vdevSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ '各接口收发统计' ]),
			E('table', { 'class': 'table' }, [
				E('thead', {}, [
					E('tr', { 'class': 'tr table-titles' }, [
						th('接口号'), th('收包'), th('收字节'), th('发包'),
						th('例外'), th('丢弃'), th('Ring 满')
					])
				]),
				E('tbody', {}, vdevRows)
			]),
			E('div', { 'class': 'cbi-value-description' }, [
				'来源 /sys/kernel/debug/39000000.nss/wifili_rx，是 NSS 固件定期同步回来的计数。',
				'「收字节」能直接对上你下载的流量，说明这些帧真的走了硬件；',
				'「例外」是 NSS 处理不了、退回内核的包；「丢弃」和「Ring 满」应该长期为 0。'
			])
		]);

		/* ---- 流表 ---- */
		var flowRows = [];

		if (flows.nodes.length === 0) {
			flowRows.push(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '4' }, [ '没有已下发的流转发节点' ])
			]));
		}
		else {
			flows.nodes.forEach(function(n) {
				flowRows.push(E('tr', { 'class': 'tr' }, [
					td(E('code', {}, [ n.name ])),
					td(fmtNum(n.rx), 'right'),
					td(fmtNum(n.tx), 'right'),
					td(n.drop, 'right')
				]));
			});
		}

		var flowSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ '流转发' ]),
			E('table', { 'class': 'table' }, [
				E('thead', {}, [
					E('tr', { 'class': 'tr table-titles' }, [
						th('节点'), th('收包'), th('发包'), th('丢弃（4 个原因）')
					])
				]),
				E('tbody', {}, flowRows)
			]),
			E('div', { 'class': 'cbi-value-description' }, [
				'来源 /sys/kernel/debug/39000000.nss/flows。bound/pushed 是主机与 NSS 之间的流绑定次数：',
				E('code', {}, [ String(flows.bound) + ' / ' + String(flows.pushed) ]),
				'。节点计数持续增长表示转发确实在硬件里跑。'
			])
		]);

		/* ---- 固件日志 ---- */
		var logSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ 'NSS 固件日志' ]),
			E('pre', {
				'style': 'max-height:300px;overflow:auto;padding:8px;border-radius:4px;' +
					'font-size:12px;line-height:1.5;background:rgba(128,128,128,0.12);' +
					'white-space:pre-wrap;word-break:break-all'
			}, [ log !== '' ? log : '(无输出)' ]),
			E('div', { 'class': 'cbi-value-description' }, [
				'取自 /sys/kernel/debug/39000000.nss/log，最近 30 行。',
				'驱动启动成功的标志在内核日志里：logread -e nss-wifi | tail -3 应能看到 ',
				E('code', {}, [ 'NSS data plane ready' ]), '。'
			])
		]);

		/* ---- 操作 ---- */
		var actions = E('div', { 'class': 'cbi-section' }, [
			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function() {
						window.location.reload();
					})
				}, [ '刷新' ])
			]),
			E('div', { 'class': 'cbi-value-description' }, [
				'这些计数器由 NSS 固件维护，页面只负责读。',
				'打开 /etc/config/nss-wifi 里的 offload 后必须整机重启才生效——',
				'Wi-Fi 环的归属在 radio probe 时就定死了，重启服务没用。'
			])
		]);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ 'NSS 卸载状态' ]),
			overview,
			vdevSection,
			flowSection,
			logSection,
			actions
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
