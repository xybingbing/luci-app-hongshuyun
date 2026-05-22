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

const css = '						\
.hongshuyun-page .cbi-map {				\
	margin-top: 8px;					\
}							\
.hongshuyun-page .cbi-section-node {			\
	padding: 14px 16px;				\
}							\
.hongshuyun-page .cbi-value {				\
	padding-top: 6px;				\
	padding-bottom: 6px;				\
}';

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

		o = s.option(form.ListValue, 'main_udp_node', _('主 UDP 节点'));
		o.value('same', _('保持与主节点一致'));
		for (let i in proxy_nodes)
			o.value(i, proxy_nodes[i]);
		o.default = 'same';
		o.rmempty = false;

		o = s.option(form.ListValue, 'dns_server', _('DNS 服务器'));
		o.value('wan', _('使用 WAN DNS'));
		o.value('8.8.8.8', _('谷歌公共 DNS (8.8.8.8)'));
		o.value('1.1.1.1', _('Cloudflare 公共 DNS (1.1.1.1)'));
		o.value('9.9.9.9', _('Quad9 公共 DNS (9.9.9.9)'));
		o.default = '8.8.8.8';
		o.rmempty = false;

		o = s.option(form.ListValue, 'china_dns_server', _('国内 DNS 服务器'));
		o.value('wan', _('使用 WAN DNS'));
		o.value('223.5.5.5', _('阿里云公共 DNS (223.5.5.5)'));
		o.value('119.29.29.29', _('腾讯公共 DNS (119.29.29.29)'));
		o.value('114.114.114.114', _('114DNS (114.114.114.114)'));
		o.default = '223.5.5.5';
		o.rmempty = false;

		return m.render().then((node) => {
			return E([
				E('style', [ css ]),
				E('div', { 'class': 'hongshuyun-page' }, [ node ])
			]);
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
