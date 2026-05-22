/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require dom';
'require form';
'require fs';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

const css = '				\
#log_textarea {				\
	padding: 10px;			\
	text-align: left;		\
}					\
#log_textarea pre {			\
	padding: .5rem;			\
	word-break: break-all;		\
	margin: 0;			\
}';

const run_dir = '/var/run/hongshuyun';

const callLogClean = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'log_clean',
	params: ['type'],
	expect: { '': {} }
});

const callConnStat = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'connection_check',
	params: ['target'],
	expect: { '': {} }
});

const callResVersion = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'resources_get_version',
	expect: { '': {} }
});

const callResUpdate = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'resources_update',
	params: ['type'],
	expect: { '': {} }
});

function getConnStat(o, site) {
	o.default = E('div', { 'style': 'cbi-value-field' }, [
		E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, () => {
				return L.resolveDefault(callConnStat(site), {}).then((ret) => {
					let ele = o.default.firstElementChild.nextElementSibling;
					if (ret.result) {
						ele.style.setProperty('color', 'green');
						ele.innerHTML = _('正常');
					} else {
						ele.style.setProperty('color', 'red');
						ele.innerHTML = _('失败');
					}
				});
			})
		}, [ _('检查') ]),
		' ',
		E('strong', { 'style': 'color:gray' }, _('未检查')),
	]);
}

function getResVersion(o, type) {
	return L.resolveDefault(callResVersion(), {}).then((res) => {
		const version = res?.[type];
		let spanTemp = E('div', { 'style': 'cbi-value-field' }, [
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, () => {
					return L.resolveDefault(callResUpdate(type), {}).then((res2) => {
						if (res2?.result) {
							if (res2?.updated)
								o.description = _('更新成功');
							else
								o.description = _('已是最新版本');
						} else {
							o.description = _('更新失败') + (res2?.error ? (': ' + res2.error) : '');
						}

						return o.map.reset();
					});
				})
			}, [ _('检查更新') ]),
			' ',
			E('strong', { 'style': (version ? 'color:green' : 'color:red') },
				[ version ? version : 'not found' ]
			),
		]);

		o.default = spanTemp;
	});
}

function getRuntimeLog(o, name) {
	const filename = o.option.split('_')[1];

	const log_textarea = E('div', { 'id': 'log_textarea' },
		E('img', {
			'src': L.resource('icons/loading.svg'),
			'alt': _('Loading'),
			'style': 'vertical-align:middle'
		}, _('Collecting data...'))
	);

	let log;
	poll.add(L.bind(() => {
		return fs.read_direct(String.format('%s/%s.log', run_dir, filename), 'text')
		.then((res) => {
			log = E('pre', { 'wrap': 'pre' }, [
				res.trim() || _('Log is empty.')
			]);

			dom.content(log_textarea, log);
		}).catch((err) => {
			if (err.toString().includes('NotFoundError'))
				log = E('pre', { 'wrap': 'pre' }, [
					_('Log file does not exist.')
				]);
			else
				log = E('pre', { 'wrap': 'pre' }, [
					_('Unknown error: %s').format(err)
				]);

			dom.content(log_textarea, log);
		});
	}));

	return E([
		E('style', [ css ]),
		E('div', {'class': 'cbi-map'}, [
			E('h3', {'name': 'content', 'style': 'align-items: center; display: flex;'}, [
				_('%s 日志').format(name),
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'style': 'margin-left: 4px;',
					'click': ui.createHandlerFn(this, () => {
						return L.resolveDefault(callLogClean(filename), {});
					})
				}, [ _('清除') ])
			]),
			E('div', {'class': 'cbi-section'}, [
				log_textarea,
				E('div', {'style': 'text-align:right'},
					E('small', {}, _('每 %s 秒刷新一次。').format(L.env.pollinterval))
				)
			])
		])
	]);
}

return view.extend({
	render() {
		let m, s, o;

		m = new form.Map('hongshuyun');

		s = m.section(form.NamedSection, 'config', 'hongshuyun', _('连接检查'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_check_baidu', _('百度'));
		o.cfgvalue = L.bind(getConnStat, this, o, 'baidu');

		o = s.option(form.DummyValue, '_check_google', _('谷歌'));
		o.cfgvalue = L.bind(getConnStat, this, o, 'google');

		s = m.section(form.NamedSection, 'config', 'hongshuyun', _('资源管理'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_china_ip4_version', _('国内 IPv4 库版本'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_ip4');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_china_ip6_version', _('国内 IPv6 库版本'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_ip6');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_china_list_version', _('国内域名列表版本'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_list');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_gfw_list_version', _('GFW 域名列表版本'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'gfw_list');
		o.rawhtml = true;

		o = s.option(form.Value, 'github_token', _('GitHub 令牌'));
		o.password = true;
		o.renderWidget = function() {
			let node = form.Value.prototype.renderWidget.apply(this, arguments);

			(node.querySelector('.control-group') || node).appendChild(E('button', {
				'class': 'cbi-button cbi-button-apply',
				'title': _('保存'),
				'click': ui.createHandlerFn(this, () => {
					return this.map.save(null, true).then(() => {
						ui.changes.apply(true);
					});
				}, this.option)
			}, [ _('保存') ]));

			return node;
		}

		s = m.section(form.NamedSection, 'config', 'hongshuyun');
		s.anonymous = true;

		o = s.option(form.DummyValue, '_hongshuyun_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('红薯云'));

		o = s.option(form.DummyValue, '_sing-box-c_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('sing-box client'));

		return m.render();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
