/*
 * Copyright (C) 2021-2025 ImmortalWrt
 */

'use strict';

function read_file(path) {
	let f;
	try {
		f = new File(path, "r");
		let s = f.read();
		f.close();
		return s.trim();
	} catch(e) {
		return null;
	}
}

function get_cpu_temp() {
	/* IPQ60xx 优先读取 thermal_zone0，tsens‑ipq60xx type不包含cpu，绕过原type匹配 */
	let val = read_file("/sys/class/thermal/thermal_zone0/temp");
	if (val) {
		let t = Number(val);
		if (t > 0)
			return Math.round(t / 1000);
	}

	let dir = new Directory("/sys/class/thermal");
	for (let entry of dir) {
		if (!entry.name.startsWith("thermal_zone"))
			continue;

		let type = read_file("/sys/class/thermal/" + entry.name + "/type");
		if (type && type.toLowerCase().indexOf("cpu") !== -1) {
			let temp = read_file("/sys/class/thermal/" + entry.name + "/temp");
			if (temp) {
				let t = Number(temp);
				if (t > 0)
					return Math.round(t / 1000);
			}
		}
	}

	/* fallback hwmon */
	dir = new Directory("/sys/class/hwmon");
	for (let entry of dir) {
		let name = read_file("/sys/class/hwmon/" + entry.name + "/name");
		if (!name) continue;
		name = name.toLowerCase();
		if (name.indexOf("tsens") !== -1 || name.indexOf("cpu") !== -1 || name.indexOf("soc") !== -1) {
			let temp = read_file("/sys/class/hwmon/" + entry.name + "/temp1_input");
			if (temp) {
				let t = Number(temp);
				if (t > 0)
					return Math.round(t / 1000);
			}
		}
	}
	return null;
}

function get_cpuinfo() {
	let cpuinfo = read_file("/proc/cpuinfo");
	if (!cpuinfo)
		return null;

	let ret = {
		model: null,
		cores: 0,
		freq: 0
	};

	let lines = cpuinfo.split('\n');
	for (let line of lines) {
		if (line.startsWith('model name') || line.startsWith('Processor')) {
			let m = line.split(':');
			if (m.length > 1)
				ret.model = m[1].trim();
		}
		if (line.startsWith('processor'))
			ret.cores += 1;
	}

	/* cpu freq */
	let f = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq");
	if (f)
		ret.freq = Math.round(Number(f)/1000);

	return ret;
}

function get_loadavg() {
	let la = read_file("/proc/loadavg");
	if (!la) return null;
	let arr = la.split(/\s+/);
	return {
		load1: Number(arr[0]),
		load5: Number(arr[1]),
		load15: Number(arr[2])
	};
}

function get_meminfo() {
	let raw = read_file("/proc/meminfo");
	if (!raw) return null;
	let mem = {};
	raw.split('\n').forEach(function(line) {
		let kv = line.split(':');
		if (kv.length <2) return;
		let k = kv[0].trim();
		let v = parseInt(kv[1].trim());
		mem[k] = v;
	});
	return {
		total: mem.MemTotal * 1024,
		free: mem.MemFree *1024,
		buffers: mem.Buffers *1024,
		cached: mem.Cached *1024
	};
}

function get_swapinfo() {
	let raw = read_file("/proc/meminfo");
	if (!raw) return null;
	let mem = {};
	raw.split('\n').forEach(function(line) {
		let kv = line.split(':');
		if (kv.length <2) return;
		let k = kv[0].trim();
		let v = parseInt(kv[1].trim());
		mem[k] = v;
	});
	return {
		total: mem.SwapTotal *1024,
		free: mem.SwapFree *1024
	};
}

module.exports = {
	get_cpu_temp: get_cpu_temp,
	get_cpuinfo: get_cpuinfo,
	get_loadavg: get_loadavg,
	get_meminfo: get_meminfo,
	get_swapinfo: get_swapinfo
};
