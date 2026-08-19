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

	/* 保留原有逻辑做兜底，兼容其他平台 */
	let dir = new Dir("/sys/class/thermal");
	for (let ent of dir) {
		if (!ent.name.startsWith("thermal_zone"))
			continue;

		let type = read_file("/sys/class/thermal/" + ent.name + "/type");
		if (!type || !type.includes("cpu"))
			continue;

		let raw = read_file("/sys/class/thermal/" + ent.name + "/temp");
		if (!raw) continue;
		let t = Number(raw);
		if (t > 0)
			return Math.round(t / 1000);
	}
	return null;
}

function get_cpu_usage() {
	let s = read_file("/proc/stat");
	if (!s) return null;
	let m = s.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/);
	if (!m) return null;
	let user = Number(m[1]), nice = Number(m[2]), system = Number(m[3]), idle = Number(m[4]);
	let total = user + nice + system + idle;
	return { user, nice, system, idle, total };
}

function get_mem_info() {
	let s = read_file("/proc/meminfo");
	if (!s) return null;
	let mem = {};
	for (let line of s.split("\n")) {
		let kv = line.match(/^(.+?):\s*(\d+)/);
		if (!kv) continue;
		mem[kv[1]] = Number(kv[2]) * 1024;
	}
	let total = mem.MemTotal;
	let free = mem.MemFree + mem.Buffers + mem.Cached;
	let used = total - free;
	return { total, used };
}

function main() {
	let rv = {};
	rv.cpu_temp = get_cpu_temp();
	rv.cpu_usage = get_cpu_usage();
	rv.mem_info = get_mem_info();
	return rv;
}

print(JSON.stringify(main()));
