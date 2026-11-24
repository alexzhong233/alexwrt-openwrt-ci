'use strict';
'require baseclass';
'require fs';

/* LuCI 状态 → 概览插件：eMMC 寿命速览 */

var C_OK = '#43a047';
var C_WARN = '#fb8c00';
var C_BAD = '#e53935';

function hexValue(v) {
	if (v == null)
		return null;

	var m = String(v).match(/0x([0-9a-fA-F]+)/);
	var n = m ? parseInt(m[1], 16) : parseInt(v, 10);

	return isNaN(n) ? null : n;
}

function formatSize(sizeBytes) {
	var b = Number(sizeBytes);

	if (!isFinite(b) || b <= 0)
		return '未知';

	return (b / (1024 * 1024 * 1024)).toFixed(2) + ' GiB';
}

function mmcRev(rev) {
	if (!rev)
		return '';

	var m = String(rev).match(/\(([^)]+)\)/);

	return m ? m[1] : String(rev);
}

function preEolInfo(v) {
	var n = hexValue(v);

	switch (n) {
	case 2:
		return { color: C_WARN, text: (v || '0x02') + ' · 警告（备用块消耗 80%–90%）' };
	case 3:
		return { color: C_BAD, text: (v || '0x03') + ' · 严重（备用块消耗 >90%）' };
	default:
		return { color: C_OK, text: (v || '0x01') + ' · 正常（备用块消耗 <80%）' };
	}
}

function lifeInfo(v) {
	var n = hexValue(v);

	if (n == null)
		return { pct: 0, color: C_OK, text: (v || '-') + ' · 未知' };

	if (n >= 0x0b)
		return { pct: 100, color: C_BAD, text: '0x0b · >100%（超出预估寿命）' };

	if (n < 1)
		n = 1;

	return {
		pct: n * 10,
		color: n >= 9 ? C_WARN : C_OK,
		text: (v || ('0x' + n.toString(16))) + ' · ' + ((n - 1) * 10) + '–' + (n * 10) + '%'
	};
}

function progressBar(pct, color) {
	return E('div', {
		'class': 'progress',
		'style': 'height:6px;margin-top:3px;background:rgba(128,128,128,0.18);border-radius:3px;overflow:hidden'
	}, [
		E('div', {
			'class': 'progress-bar',
			'style': 'width:' + pct + '%;height:100%;background:' + color + ';border-radius:3px'
		})
	]);
}

return baseclass.extend({
	title: _('eMMC 寿命'),

	load: function() {
		return fs.exec('/bin/sh', [ '/usr/libexec/emmc-health-info' ])
			.then(function(res) {
				var data;

				if (!res || res.code !== 0 || !res.stdout)
					return null;

				try {
					data = JSON.parse(res.stdout);
				}
				catch (e) {
					return null;
				}

				if (!data || !Array.isArray(data.devices) || data.devices.length === 0)
					return null;

				return data;
			})
			.catch(function() {
				return null;
			});
	},

	render: function(data) {
		var rows = function(label, value) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '34%' }, [ label ]),
				E('td', { 'class': 'td left' }, [ value ])
			]);
		};

		var lifeRow = function(label, info) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '34%' }, [ label ]),
				E('td', { 'class': 'td left' }, [
					E('span', { 'style': 'color:' + info.color + ';font-weight:bold' }, [ info.text ]),
					progressBar(info.pct, info.color)
				])
			]);
		};

		var sections = data.devices.map(function(dev) {
			var rev = mmcRev(dev.ext_csd_rev);
			var head = (dev.name || dev.device || 'eMMC') + ' · ' +
				(dev.vendor || 'Unknown') + ' · ' + formatSize(dev.size_bytes) +
				(rev ? ' (' + rev + ')' : '');
			var pe = preEolInfo(dev.pre_eol);

			return E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ head ]),
				E('table', { 'class': 'table' }, [
					rows('设备节点', E('code', {}, [ '/dev/' + (dev.device || '?') ])),
					rows('备用块 / Pre-EOL', E('span', {
						'style': 'color:' + pe.color + ';font-weight:bold'
					}, [ pe.text ])),
					lifeRow('Type A（SLC / 增强区）', lifeInfo(dev.life_a)),
					lifeRow('Type B（MLC / TLC 主存储）', lifeInfo(dev.life_b))
				])
			]);
		});

		sections.push(E('div', { 'class': 'cbi-value-description', 'style': 'margin-top:4px' }, [
			E('a', { 'href': L.url('admin/status/emmc-health') }, [ '查看详细监测与写入统计 →' ])
		]));

		return E('div', {}, sections);
	}
});
