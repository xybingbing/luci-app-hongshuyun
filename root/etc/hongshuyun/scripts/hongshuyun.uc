/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

import { mkstemp, open } from 'fs';
import { urldecode_params } from 'luci.http';

export const HP_DIR = '/etc/hongshuyun';
export const RUN_DIR = '/var/run/hongshuyun';

export function shellQuote(s) {
	return `'${replace(s, "'", "'\\''")}'`;
};

export function isBinary(str) {
	for (let off = 0, byte = ord(str); off < length(str); byte = ord(str, ++off))
		if (byte <= 8 || (byte >= 14 && byte <= 31))
			return true;

	return false;
};

export function executeCommand(...args) {
	let outfd = mkstemp();
	let errfd = mkstemp();

	const exitcode = system(`${join(' ', args)} >&${outfd.fileno()} 2>&${errfd.fileno()}`);

	outfd.seek(0);
	errfd.seek(0);

	const stdout = outfd.read(1024 * 1024 * 2) ?? '';
	const stderr = errfd.read(1024 * 256) ?? '';

	outfd.close();
	errfd.close();

	const binary = isBinary(stdout);

	return {
		command: join(' ', args),
		stdout: binary ? null : stdout,
		stderr,
		exitcode,
		binary
	};
};

export function getTime(epoch) {
	const local_time = localtime(epoch);
	return replace(replace(sprintf(
		'%d-%2d-%2d@%2d:%2d:%2d',
		local_time.year,
		local_time.mon,
		local_time.mday,
		local_time.hour,
		local_time.min,
		local_time.sec
	), ' ', '0'), '@', ' ');
};

export function httpGET(url, headers, ua) {
	if (!url || type(url) !== 'string')
		return null;

	if (!ua)
		ua = 'Wget/1.21 (Hongshuyun)';

	let header_args = '';
	if (headers && type(headers) === 'object')
		for (let k in keys(headers))
			header_args += ` --header ${shellQuote(k + ': ' + headers[k])}`;

	const output = executeCommand(`/usr/bin/wget -qO- --user-agent ${shellQuote(ua)} --timeout=10${header_args} ${shellQuote(url)}`) || {};
	if (output.stdout === null)
		return null;
	return trim(output.stdout);
};

export function httpPOST(url, body, headers, ua) {
	if (!url || type(url) !== 'string')
		return null;

	if (!ua)
		ua = 'Wget/1.21 (Hongshuyun)';

	let header_args = '';
	if (headers && type(headers) === 'object')
		for (let k in keys(headers))
			header_args += ` --header ${shellQuote(k + ': ' + headers[k])}`;

	const output = executeCommand(`/usr/bin/wget -qO- --user-agent ${shellQuote(ua)} --timeout=10 --post-data ${shellQuote(body || '')}${header_args} ${shellQuote(url)}`) || {};
	if (output.stdout === null)
		return null;
	return trim(output.stdout);
};

export function getEpoch() {
	const output = executeCommand('/bin/date +%s') || {};
	return int(trim(output.stdout)) || 0;
};

function readBytes(device, offset, length) {
	let f;
	try {
		f = open(device, 'r');
		f.seek(offset);
		const buf = f.read(length);
		f.close();
		return buf;
	} catch (e) {
		try { if (f) f.close(); } catch (e2) {}
		return null;
	}
}

export function getFactoryInfo() {
	const FactoryPartition = '/dev/mtd2';
	const PCBSNOffset = 0x3FF00;
	const PCBSNLength = 15;
	const BatchOffset = 0x3FF10;
	const BatchLength = 14;
	const MAC4Offset = 0x3FFFA;
	const MACLength = 6;

	let pcb_sn = readBytes(FactoryPartition, PCBSNOffset, PCBSNLength);
	let batch_no = readBytes(FactoryPartition, BatchOffset, BatchLength);
	let mac_bytes = readBytes(FactoryPartition, MAC4Offset, MACLength);

	if (!pcb_sn || !batch_no || !mac_bytes)
		return null;

	pcb_sn = replace(pcb_sn, /[\x00\xff]+$/g, '');
	batch_no = replace(batch_no, /[\x00\xff]+$/g, '');

	let mac = [];
	for (let i = 0; i < MACLength; i++)
		push(mac, sprintf('%02X', ord(mac_bytes, i)));

	return {
		pcb_sn,
		batch_no,
		mac: join(':', mac)
	};
};

export function isEmpty(res) {
	return !res || res === 'nil' || (type(res) in ['array', 'object'] && length(res) === 0);
};

export function strToBool(str) {
	return (str === '1') || null;
};

export function strToInt(str) {
	return !isEmpty(str) ? (int(str) || null) : null;
};

export function strToTime(str) {
	return !isEmpty(str) ? (str + 's') : null;
};

export function removeBlankAttrs(res) {
	let content;

	if (type(res) === 'object') {
		content = {};
		map(keys(res), (k) => {
			if (type(res[k]) in ['array', 'object'])
				content[k] = removeBlankAttrs(res[k]);
			else if (res[k] !== null && res[k] !== '')
				content[k] = res[k];
		});
	} else if (type(res) === 'array') {
		content = [];
		map(res, (k, i) => {
			if (type(k) in ['array', 'object'])
				push(content, removeBlankAttrs(k));
			else if (k !== null && k !== '')
				push(content, k);
		});
	} else
		return res;

	return content;
};

export function validation(datatype, data) {
	if (!datatype || !data)
		return null;

	const ret = system(`/sbin/validate_data ${shellQuote(datatype)} ${shellQuote(data)} 2>/dev/null`);
	return (ret === 0);
};

export function decodeBase64Str(str) {
	if (isEmpty(str))
		return null;

	str = trim(str);
	str = replace(str, '_', '/');
	str = replace(str, '-', '+');

	const padding = length(str) % 4;
	if (padding)
		str = str + substr('====', padding);

	return b64dec(str);
};

export function parseURL(url) {
	if (type(url) !== 'string')
		return null;

	const services = {
		http: '80',
		https: '443'
	};

	const objurl = {};

	objurl.href = url;

	url = replace(url, /#(.+)$/, (_, val) => {
		objurl.hash = val;
		return '';
	});

	url = replace(url, /^(\w[A-Za-z0-9\+\-\.]+):/, (_, val) => {
		objurl.protocol = val;
		return '';
	});

	url = replace(url, /\?(.+)/, (_, val) => {
		objurl.search = val;
		objurl.searchParams = urldecode_params(val);
		return '';
	});

	url = replace(url, /^\/\/([^\/]+)/, (_, val) => {
		val = replace(val, /^([^@]+)@/, (_, val) => {
			objurl.userinfo = val;
			return '';
		});

		val = replace(val, /:(\d+)$/, (_, val) => {
			objurl.port = val;
			return '';
		});

		if (validation('ip4addr', val) ||
		    validation('ip6addr', replace(val, /\[|\]/g, '')) ||
		    validation('hostname', val))
			objurl.hostname = val;

		return '';
	});

	objurl.pathname = url || '/';

	if (!objurl.protocol || !objurl.hostname)
		return null;

	if (objurl.userinfo) {
		objurl.userinfo = replace(objurl.userinfo, /:(.+)$/, (_, val) => {
			objurl.password = val;
			return '';
		});

		if (match(objurl.userinfo, /^[A-Za-z0-9\+\-\_\.]+$/)) {
			objurl.username = objurl.userinfo;
			delete objurl.userinfo;
		} else {
			delete objurl.userinfo;
			delete objurl.password;
		}
	};

	if (!objurl.port)
		objurl.port = services[objurl.protocol];

	objurl.host = objurl.hostname + (objurl.port ? `:${objurl.port}` : '');
	objurl.origin = `${objurl.protocol}://${objurl.host}`;

	return objurl;
};
