/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require form';
'require poll';
'require rpc';
'require uci';
'require view';

'require hongshuyun as hp';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

function getServiceStatus() {
	return L.resolveDefault(callServiceList('hongshuyun'), {}).then((res) => {
		let isRunning = false;
		try {
			isRunning = res['hongshuyun']['instances']['sing-box-c']['running'];
		} catch (e) { }
		return isRunning;
	});
}

function renderStatus(isRunning, version) {
	let spanTemp = '<em><span style="color:%s"><strong>%s (sing-box v%s) %s</strong></span></em>';
	return spanTemp.format(isRunning ? 'green' : 'red', _('红薯云'), version || '-', isRunning ? _('RUNNING') : _('NOT RUNNING'));
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('hongshuyun'),
			hp.getBuiltinFeatures()
		]);
	},

	render(data) {
		let m, s, o;

		let features = data[1] || {};

		let proxy_nodes = {};
		uci.sections(data[0], 'node', (res) => {
			let nodeaddr = res.address || '';
			let nodeport = res.port || '';
			proxy_nodes[res['.name']] = res.label || (nodeaddr && nodeport ? (nodeaddr + ':' + nodeport) : res['.name']);
		});

		m = new form.Map('hongshuyun', _('红薯云'), _('红薯云代理平台'));

		s = m.section(form.TypedSection);
		s.render = function () {
			poll.add(function () {
				return L.resolveDefault(getServiceStatus()).then((res) => {
					let view = document.getElementById('service_status');
					if (view)
						view.innerHTML = renderStatus(res, features.version);
				});
			});

			return E('div', { class: 'cbi-section', id: 'status_bar' }, [
				E('p', { id: 'service_status' }, _('Collecting data...'))
			]);
		};

		s = m.section(form.NamedSection, 'config', 'hongshuyun', _('客户端设置'));
		s.anonymous = true;

		o = s.option(form.ListValue, 'main_node', _('主节点'));
		o.value('nil', _('禁用'));
		for (let i in proxy_nodes)
			o.value(i, proxy_nodes[i]);
		o.default = 'nil';
		o.rmempty = false;

		return m.render();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
