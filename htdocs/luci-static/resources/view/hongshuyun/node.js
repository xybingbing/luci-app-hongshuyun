/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require form';
'require fs';
'require uci';
'require ui';
'require view';

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

return view.extend({
	load() {
		return Promise.all([
			uci.load('hongshuyun')
		]);
	},

	render() {
		let m, s, o;

		m = new form.Map('hongshuyun', _('节点设置'));

		s = m.section(form.NamedSection, 'subscription', 'hongshuyun', _('红薯云'));
		s.anonymous = true;

		o = s.option(form.Flag, 'hongshuyun_enable', _('启用'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.option(form.Value, 'hongshuyun_api', _('接口地址'));
		o.default = 'http://api.hongshu.one';
		o.rmempty = false;

		o = s.option(form.Button, '_sync', _('同步节点'));
		o.inputstyle = 'apply';
		o.inputtitle = _('立即同步');
		o.depends('hongshuyun_enable', '1');
		o.onclick = function() {
			return this.map.save(null, true).then(() => {
				return fs.exec_direct('/etc/hongshuyun/scripts/update_subscriptions.uc').then(() => {
					return location.reload();
				});
			}).catch((err) => {
				ui.addNotification(null, E('p', _('同步失败：%s').format(err)));
				return this.map.reset();
			});
		};

		s = m.section(form.GridSection, 'node', _('节点列表'));
		s.anonymous = true;
		s.addremove = false;
		s.sortable = false;

		o = s.option(form.DummyValue, 'label', _('名称'));
		o.cfgvalue = function(section_id) {
			return uci.get('hongshuyun', section_id, 'label') || section_id;
		};

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
