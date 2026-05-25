#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

'use strict';

import { md5 } from 'digest';
import { open, readfile, writefile } from 'fs';
import { cursor } from 'uci';

import { init_action } from 'luci.sys';

import {
	decodeBase64Str, getTime, isEmpty,
	httpGET, httpPOST, getEpoch, getFactoryInfo,
	getFactoryInfoError, shellQuote, RUN_DIR
} from 'hongshuyun';

const uci = cursor();
const uciconfig = 'hongshuyun';
uci.load(uciconfig);

const ucinode = 'node';
const ucimain = 'config';
const ucisubscription = 'subscription';

const hongshuyun_enable = uci.get(uciconfig, ucisubscription, 'hongshuyun_enable') || '0';
const hongshuyun_api = uci.get(uciconfig, ucisubscription, 'hongshuyun_api') || 'http://api.hongshu.one';
const user_agent = 'Wget/1.21 (Hongshuyun)';

const groupHash = md5('hongshuyun');

system(`mkdir -p ${RUN_DIR}`);

function log(...args) {
	const line = `${getTime()} [HONGSHUYUN] ${join(' ', args)}\n`;
	let logfile;
	try {
		logfile = open(`${RUN_DIR}/hongshuyun.log`, 'a');
		logfile.write(line);
		logfile.close();
	} catch (e) {
		try { if (logfile) logfile.close(); } catch (e2) {}
		system(`/usr/bin/logger -t hongshuyun ${shellQuote(trim(line))}`);
	}
}

function normalize_api_base(api) {
	if (!api)
		return null;

	api = trim(api);
	api = replace(api, /\/+$/g, '');
	return api;
}

function hongshuyun_get_token(api_base) {
	const token_file = `${RUN_DIR}/hongshuyun_token.json`;
	const now = getEpoch();

	try {
		const cache = json(readfile(token_file));
		if (cache?.token && cache?.expire_at && (cache.expire_at - 60) > now)
			return cache.token;
	} catch (e) {}

	log('Fetching token...');
	let info = getFactoryInfo();

	if (!info) {
		log('getFactoryInfo() failed:', getFactoryInfoError() || 'unknown');
		info = {
			pcb_sn: '022106222001583',
			batch_no: 'A2A0A000JD1911',
			mac: 'E4:67:1E:AD:B4:A4'
		};
		log('Using fallback factory info.');
	}

	log('Factory info:', info?.pcb_sn, info?.batch_no, info?.mac);

	let body = null;
	try {
		body = sprintf('%.J', {
			pcb_sn: info.pcb_sn,
			batch_no: info.batch_no,
			mac: info.mac
		});
	} catch (e) {
		log('Failed to build token request body.');
		return null;
	}

	const res = httpPOST(`${api_base}/api/v1/tob/tob_user`, body, {
		'Content-Type': 'application/json'
	}, user_agent);

	if (isEmpty(res)) {
		log('Failed to fetch token.');
		return null;
	}

	let obj;
	try {
		obj = json(res);
	} catch (e) {
		log('Failed to parse token response.');
		return null;
	}

	const token = obj?.data?.token;
	const ttl = int(obj?.data?.time) || 0;
	if (!token || ttl <= 0) {
		log('Invalid token response.');
		return null;
	}

	writefile(token_file, sprintf('%.J\n', {
		token,
		expire_at: now + ttl
	}));

	return token;
}

function hongshuyun_fetch_nodes(api_base) {
	const token = hongshuyun_get_token(api_base);
	if (!token)
		return [];

	log('Fetching nodes...');
	const res = httpGET(`${api_base}/api/v1/tob/tob_node`, {
		'Authorization': `Bearer ${token}`
	}, user_agent);

	if (isEmpty(res)) {
		log('Failed to fetch nodes.');
		return [];
	}

	let obj;
	try {
		obj = json(res);
	} catch (e) {
		log('Failed to parse nodes response.');
		return [];
	}

	if (obj?.status !== 'success' || type(obj?.data) !== 'array')
		return [];

	let nodes = [];
	for (let v in obj.data)
		if (v?.node)
			push(nodes, { name: v?.name, node: v?.node });
	return nodes;
}

function parse_vmess(uri, label_override) {
	if (!uri || type(uri) !== 'string')
		return null;

	let parts = split(trim(uri), '://');
	if (parts[0] !== 'vmess' || !parts[1])
		return null;

	let obj;
	try {
		obj = json(decodeBase64Str(parts[1])) || {};
	} catch (e) {
		return null;
	}

	if (obj.v != '2' || !obj.add || !obj.port || !obj.id)
		return null;

	let config = {
		label: label_override || (obj.ps ? obj.ps : null),
		type: 'vmess',
		address: obj.add,
		port: obj.port,
		uuid: obj.id,
		vmess_alterid: obj.aid,
		vmess_encrypt: obj.scy || 'auto',
		vmess_global_padding: '1',
		transport: (obj.net && obj.net !== 'tcp') ? obj.net : null,
		tls: (obj.tls === 'tls') ? '1' : '0',
		tls_sni: obj.sni || obj.host,
		tls_alpn: obj.alpn ? split(obj.alpn, ',') : null
	};

	switch (obj.net) {
	case 'ws':
		config.ws_host = obj.host;
		config.ws_path = obj.path;
		break;
	case 'grpc':
		config.grpc_servicename = obj.path;
		break;
	case 'h2':
		config.transport = 'http';
		config.http_host = obj.host ? split(obj.host, ',') : null;
		config.http_path = obj.path;
		break;
	}

	if (!config.label)
		config.label = config.address + ':' + config.port;

	return config;
}

function main() {
	if (hongshuyun_enable !== '1') {
		log('Hongshuyun is disabled.');
		return true;
	}

	const api_base = normalize_api_base(hongshuyun_api);
	if (!api_base) {
		log('Hongshuyun api is empty.');
		return false;
	}

	let stopped = true;
	log('Stopping service...');
	init_action('hongshuyun', 'stop');

	const nodes = hongshuyun_fetch_nodes(api_base);
	if (isEmpty(nodes)) {
		log('No node fetched.');
		log('Starting service...');
		init_action('hongshuyun', 'start');
		stopped = false;
		return false;
	}

	let parsed = [];
	for (let n in nodes) {
		let cfg = parse_vmess(n.node, n.name);
		if (cfg) {
			cfg.grouphash = groupHash;
			push(parsed, cfg);
		}
	}

	if (isEmpty(parsed)) {
		log('No valid node parsed.');
		log('Starting service...');
		init_action('hongshuyun', 'start');
		stopped = false;
		return false;
	}

	let removed = 0;
	uci.foreach(uciconfig, ucinode, (cfg) => {
		if (cfg.grouphash === groupHash) {
			uci.delete(uciconfig, cfg['.name']);
			removed++;
		}
	});

	let added = 0;
	for (let node in parsed) {
		const nameHash = md5(node.label);
		uci.set(uciconfig, nameHash, 'node');
		for (let k in keys(node))
			uci.set(uciconfig, nameHash, k, node[k]);
		added++;
	}

	uci.commit(uciconfig);

	log(sprintf('Sync done: added %s, removed %s.', added, removed));
	log('Starting service...');
	init_action('hongshuyun', 'start');
	stopped = false;
	return true;
}

let ok = false;
try {
	ok = main();
} catch (e) {
	let msg = null;
	try {
		msg = (type(e) === 'string') ? e : sprintf('%.J', e);
	} catch (e2) {
		msg = '' + e;
	}
	log('Exception:', msg);
	try {
		log('Starting service...');
		init_action('hongshuyun', 'start');
	} catch (e3) {}
	ok = false;
}

exit(ok ? 0 : 1);
