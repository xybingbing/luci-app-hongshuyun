/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require dom';
'require fs';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

const run_dir = '/var/run/hongshuyun';

const callLogClean = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'log_clean',
	params: ['type'],
	expect: { '': {} }
});

const callConnectionCheck = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'connection_check',
	params: ['target'],
	expect: { '': {} }
});

const callResourcesGetVersion = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'resources_get_version',
	expect: { '': {} }
});

const callResourcesUpdate = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'resources_update',
	params: ['type'],
	expect: { '': {} }
});

function renderLogView(logName, fileBase) {
	const log_textarea = E('div', { 'style': 'margin-top: 8px;' },
		E('img', {
			'src': L.resource('icons/loading.svg'),
			'alt': _('Loading'),
			'style': 'vertical-align:middle'
		}, _('Collecting data...'))
	);

	let log;
	poll.add(L.bind(() => {
		return fs.read_direct(String.format('%s/%s.log', run_dir, fileBase), 'text')
		.then((res) => {
			log = E('pre', { 'wrap': 'pre' }, [ res.trim() || _('Log is empty.') ]);
			dom.content(log_textarea, log);
		}).catch((err) => {
			log = E('pre', { 'wrap': 'pre' }, [ _('Log file does not exist.') ]);
			dom.content(log_textarea, log);
		});
	}));

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', { 'style': 'display:flex;align-items:center;gap:8px;' }, [
			E('span', [ logName ]),
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, () => {
					return L.resolveDefault(callLogClean(fileBase), {}).then(() => {
						if (log)
							dom.content(log_textarea, E('pre', { 'wrap': 'pre' }, [ '' ]));
					});
				})
			}, [ _('Clear') ])
		]),
		log_textarea
	]);
}

function renderConnectionCheck() {
	const baiduStat = E('span', { 'style': 'min-width: 80px;' }, [ _('未检查') ]);
	const googleStat = E('span', { 'style': 'min-width: 80px;' }, [ _('未检查') ]);

	function setStat(el, ok) {
		if (ok === true) {
			el.style.color = 'var(--success-color, #46a546)';
			el.textContent = _('正常');
		} else if (ok === false) {
			el.style.color = 'var(--error-color, #d43f3a)';
			el.textContent = _('失败');
		} else {
			el.style.color = '';
			el.textContent = _('未检查');
		}
	}

	function doCheck(target, el, btn) {
		btn.disabled = true;
		el.style.color = '';
		el.textContent = _('检查中...');

		return L.resolveDefault(callConnectionCheck(target), {})
			.then((res) => {
				setStat(el, res?.result === true);
			})
			.catch(() => {
				setStat(el, false);
			})
			.finally(() => {
				btn.disabled = false;
			});
	}

	const baiduBtn = E('button', {
		'class': 'btn cbi-button cbi-button-action',
		'click': function() { return doCheck('baidu', baiduStat, this); }
	}, [ _('检查') ]);

	const googleBtn = E('button', {
		'class': 'btn cbi-button cbi-button-action',
		'click': function() { return doCheck('google', googleStat, this); }
	}, [ _('检查') ]);

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', [ _('连接检查') ]),
		E('div', { 'class': 'cbi-section-node' }, [
			E('div', { 'style': 'display:flex;align-items:center;gap:12px;margin:6px 0;' }, [
				E('div', { 'style': 'min-width: 80px;' }, [ _('百度') ]),
				baiduBtn,
				baiduStat
			]),
			E('div', { 'style': 'display:flex;align-items:center;gap:12px;margin:6px 0;' }, [
				E('div', { 'style': 'min-width: 80px;' }, [ _('谷歌') ]),
				googleBtn,
				googleStat
			])
		])
	]);
}

function renderResourcesManage(state) {
	function setVer(el, val) {
		el.textContent = val || '-';
		el.style.color = val ? 'var(--success-color, #46a546)' : '';
	}

	function refreshVersions() {
		return L.resolveDefault(callResourcesGetVersion(), {}).then((ver) => {
			setVer(state.vers.china_ip4, ver?.china_ip4);
			setVer(state.vers.china_ip6, ver?.china_ip6);
			setVer(state.vers.china_list, ver?.china_list);
			setVer(state.vers.gfw_list, ver?.gfw_list);
		});
	}

	function runUpdate(type, btn) {
		btn.disabled = true;
		return L.resolveDefault(callResourcesUpdate(type), {}).then((res) => {
			if (res?.result) {
				if (res?.updated)
					ui.addNotification(null, E('p', [ _('更新成功') ]));
				else
					ui.addNotification(null, E('p', [ _('已是最新版本') ]));
			} else {
				ui.addNotification(null, E('p', [ _('更新失败') + (res?.error ? (': ' + res.error) : '') ]));
			}

			return refreshVersions();
		}).catch((err) => {
			ui.addNotification(null, E('p', [ _('更新失败') ]));
			throw err;
		}).finally(() => {
			btn.disabled = false;
		});
	}

	const tokenInput = state.tokenInput;
	const saveBtn = E('button', {
		'class': 'btn cbi-button cbi-button-action',
		'click': function() {
			uci.set('hongshuyun', 'config', 'github_token', (tokenInput.value || '').trim());
			return uci.save().then(() => uci.apply()).then(() => {
				ui.addNotification(null, E('p', [ _('已保存') ]));
			});
		}
	}, [ _('保存') ]);

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', [ _('资源管理') ]),
		E('div', { 'class': 'cbi-section-node' }, [
			E('div', { 'style': 'display:flex;align-items:center;gap:12px;margin:6px 0;' }, [
				E('div', { 'style': 'min-width: 160px;' }, [ _('国内 IPv4 库版本') ]),
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': function() { return runUpdate('china_ip4', this); }
				}, [ _('检查更新') ]),
				state.vers.china_ip4
			]),
			E('div', { 'style': 'display:flex;align-items:center;gap:12px;margin:6px 0;' }, [
				E('div', { 'style': 'min-width: 160px;' }, [ _('国内 IPv6 库版本') ]),
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': function() { return runUpdate('china_ip6', this); }
				}, [ _('检查更新') ]),
				state.vers.china_ip6
			]),
			E('div', { 'style': 'display:flex;align-items:center;gap:12px;margin:6px 0;' }, [
				E('div', { 'style': 'min-width: 160px;' }, [ _('国内域名列表版本') ]),
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': function() { return runUpdate('china_list', this); }
				}, [ _('检查更新') ]),
				state.vers.china_list
			]),
			E('div', { 'style': 'display:flex;align-items:center;gap:12px;margin:6px 0;' }, [
				E('div', { 'style': 'min-width: 160px;' }, [ _('GFW 域名列表版本') ]),
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': function() { return runUpdate('gfw_list', this); }
				}, [ _('检查更新') ]),
				state.vers.gfw_list
			]),
			E('div', { 'style': 'display:flex;align-items:center;gap:12px;margin:10px 0 0;' }, [
				E('div', { 'style': 'min-width: 160px;' }, [ _('GitHub 令牌') ]),
				tokenInput,
				saveBtn
			])
		])
	]);
}

return view.extend({
	render() {
		const state = {
			vers: {
				china_ip4: E('span', { 'style': 'min-width: 120px;' }, [ '-' ]),
				china_ip6: E('span', { 'style': 'min-width: 120px;' }, [ '-' ]),
				china_list: E('span', { 'style': 'min-width: 120px;' }, [ '-' ]),
				gfw_list: E('span', { 'style': 'min-width: 120px;' }, [ '-' ])
			},
			tokenInput: E('input', {
				'type': 'password',
				'class': 'cbi-input-text',
				'style': 'min-width: 320px;'
			})
		};

		return Promise.all([
			uci.load('hongshuyun'),
			L.resolveDefault(callResourcesGetVersion(), {})
		]).then(() => {
			state.tokenInput.value = uci.get('hongshuyun', 'config', 'github_token') || '';
			return L.resolveDefault(callResourcesGetVersion(), {}).then((ver) => {
				state.vers.china_ip4.textContent = ver?.china_ip4 || '-';
				state.vers.china_ip6.textContent = ver?.china_ip6 || '-';
				state.vers.china_list.textContent = ver?.china_list || '-';
				state.vers.gfw_list.textContent = ver?.gfw_list || '-';
			});
		}).then(() => {
			return E('div', { 'class': 'cbi-map' }, [
				renderConnectionCheck(),
				renderResourcesManage(state),
				renderLogView(_('红薯云'), 'hongshuyun'),
				renderLogView(_('sing-box client'), 'sing-box-c')
			]);
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
