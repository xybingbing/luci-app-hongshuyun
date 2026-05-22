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
'require ui';
'require view';

const run_dir = '/var/run/hongshuyun';

const callLogClean = rpc.declare({
	object: 'luci.hongshuyun',
	method: 'log_clean',
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

return view.extend({
	render() {
		return E('div', { 'class': 'cbi-map' }, [
			renderLogView(_('红薯云'), 'hongshuyun'),
			renderLogView(_('sing-box client'), 'sing-box-c')
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
