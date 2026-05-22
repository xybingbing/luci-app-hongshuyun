#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { writefile } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import {
	isEmpty, strToBool, strToInt, removeBlankAttrs,
	HP_DIR, RUN_DIR
} from 'hongshuyun';

const ubus = connect();
const uci = cursor();

const uciconfig = 'hongshuyun';
uci.load(uciconfig);

const uciinfra = 'infra';
const ucimain = 'config';

const ipv6_support = uci.get(uciconfig, ucimain, 'ipv6_support') || '0';
const log_level = uci.get(uciconfig, ucimain, 'log_level') || 'warn';

const main_node = uci.get(uciconfig, ucimain, 'main_node') || 'nil';

const dns_port = uci.get(uciconfig, uciinfra, 'dns_port') || '5333';
const redirect_port = uci.get(uciconfig, uciinfra, 'redirect_port') || '5331';
const tproxy_port = uci.get(uciconfig, uciinfra, 'tproxy_port') || '5332';
const self_mark = uci.get(uciconfig, uciinfra, 'self_mark') || '100';

let wan_dns = ubus.call('network.interface', 'status', { interface: 'wan' })?.['dns-server']?.[0];
if (!wan_dns)
	wan_dns = '223.5.5.5';

let dns_server = uci.get(uciconfig, ucimain, 'dns_server') || wan_dns;
if (dns_server === 'wan')
	dns_server = wan_dns;

function get_node(name) {
	if (isEmpty(name) || name === 'nil')
		return null;
	return uci.get_all(uciconfig, name);
}

function build_vmess_outbound(node) {
	if (!node || node.type !== 'vmess')
		return null;

	let outbound = {
		type: 'vmess',
		tag: 'main-out',
		server: node.address,
		server_port: strToInt(node.port),
		uuid: node.uuid,
		alter_id: strToInt(node.vmess_alterid),
		security: node.vmess_encrypt || 'auto',
		global_padding: strToBool(node.vmess_global_padding),
		tls: (node.tls === '1') ? {
			enabled: true,
			server_name: node.tls_sni,
			alpn: node.tls_alpn
		} : null,
		transport: !isEmpty(node.transport) ? {
			type: node.transport,
			host: node.http_host || node.httpupgrade_host,
			path: node.http_path || node.ws_path,
			headers: node.ws_host ? { Host: node.ws_host } : null,
			service_name: node.grpc_servicename
		} : null
	};

	return outbound;
}

const node = get_node(main_node);
if (!node) {
	writefile(RUN_DIR + '/sing-box-c.json', '');
	system(`rm -f ${RUN_DIR}/sing-box-c.json`);
	exit(1);
}

const main_out = build_vmess_outbound(node);
if (!main_out) {
	writefile(RUN_DIR + '/sing-box-c.json', '');
	system(`rm -f ${RUN_DIR}/sing-box-c.json`);
	exit(1);
}

let config = {
	log: {
		level: log_level,
		output: RUN_DIR + '/sing-box-c.log',
		timestamp: true
	},
	dns: {
		servers: [
			{
				tag: 'default-dns',
				detour: 'direct-out',
				address: dns_server
			}
		],
		rules: null,
		final: 'default-dns',
		strategy: (ipv6_support === '1') ? null : 'ipv4_only'
	},
	inbounds: [
		{
			type: 'direct',
			tag: 'dns-in',
			listen: '::',
			listen_port: int(dns_port)
		},
		{
			type: 'redirect',
			tag: 'redirect-in',
			listen: '::',
			listen_port: int(redirect_port),
			sniff: true,
			sniff_override_destination: true
		},
		{
			type: 'tproxy',
			tag: 'tproxy-in',
			listen: '::',
			listen_port: int(tproxy_port),
			network: 'udp',
			sniff: true,
			sniff_override_destination: true
		}
	],
	outbounds: [
		{
			type: 'direct',
			tag: 'direct-out',
			routing_mark: strToInt(self_mark)
		},
		{
			type: 'block',
			tag: 'block-out'
		},
		main_out
	],
	route: {
		rules: [
			{
				inbound: 'dns-in',
				action: 'hijack-dns'
			}
		],
		final: 'main-out',
		auto_detect_interface: true
	}
};

system(`mkdir -p ${RUN_DIR}`);
writefile(RUN_DIR + '/sing-box-c.json', sprintf('%.J\n', removeBlankAttrs(config)));
