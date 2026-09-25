#!/usr/bin/env bun
// universal-session-log: managed

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

type JsonObject = Record<string, any>;
type SessionRecord = { file: string; header: JsonObject; entries: JsonObject[] };
type Usage = {
	input: number;
	output: number;
	reasoning: number;
	cacheRead: number;
	cacheWrite: number;
	total: number;
	cost: number;
	models: Set<string>;
	efforts: Set<string>;
};
type Segment = { prompt: string; start: number; end: number; usage: Usage };
type Aggregate = { requests: Segment[]; usage: Usage; workMs: number; helpers: number };

const canonicalPath = (value: string): string => {
	const resolved = path.resolve(value);
	try { return fs.realpathSync.native(resolved); } catch {}
	const suffix: string[] = [];
	let current = resolved;
	while (true) {
		try {
			const canonical = fs.realpathSync.native(current);
			return path.join(canonical, ...suffix.reverse());
		} catch (error) {
			if (typeof error !== "object" || error === null || !("code" in error) || error.code !== "ENOENT") return resolved;
			const parent = path.dirname(current);
			if (parent === current) return resolved;
			suffix.push(path.basename(current));
			current = parent;
		}
	}
};
const home = canonicalPath(os.homedir());
const containsSymlinkComponent = (value: string): boolean => {
	let current = path.resolve(value);
	while (true) {
		try {
			if (fs.lstatSync(current).isSymbolicLink()) return true;
		} catch (error) {
			if (typeof error !== "object" || error === null || !("code" in error) || error.code !== "ENOENT") throw error;
		}
		const parent = path.dirname(current);
		if (parent === current) return false;
		current = parent;
	}
};
const rawDefaultAgentDir = path.join(home, ".omp", "agent");
const rawDefaultLogDir = path.join(rawDefaultAgentDir, "prompt-logs");
const rawAgentDir = process.env.PI_CODING_AGENT_DIR || rawDefaultAgentDir;
const rawLogDir = process.env.OMP_PROMPT_LOG_DIR || rawDefaultLogDir;
if (containsSymlinkComponent(rawAgentDir) || containsSymlinkComponent(rawLogDir)) throw new Error("OMP root contains an unsafe symlink");
const defaultAgentDir = path.join(home, ".omp", "agent");
const agentDir = canonicalPath(process.env.PI_CODING_AGENT_DIR || defaultAgentDir);
const defaultLogDir = path.join(defaultAgentDir, "prompt-logs");
const configuredLogDir = canonicalPath(process.env.OMP_PROMPT_LOG_DIR || defaultLogDir);
if (agentDir !== canonicalPath(defaultAgentDir) || configuredLogDir !== canonicalPath(defaultLogDir)) throw new Error("OMP root is relocated; universal session-log does not support custom roots");
const sessionsDir = path.join(agentDir, "sessions");
const validId = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
function safeSessionPath(value: string): string {
	const absolute = path.resolve(value);
	const resolved = path.join(canonicalPath(path.dirname(absolute)), path.basename(absolute));
	const rootAbsolute = path.resolve(sessionsDir);
	const root = path.join(canonicalPath(path.dirname(rootAbsolute)), path.basename(rootAbsolute));
	if (resolved !== root && !resolved.startsWith(`${root}${path.sep}`)) throw new Error(`OMP session path escapes the configured root: ${resolved}`);
	let current = root;
	try {
		if (fs.lstatSync(current).isSymbolicLink()) throw new Error(`OMP sessions root is a symlink: ${current}`);
	} catch (error) {
		if (isEnoent(error) && resolved === root) return resolved;
		if (isEnoent(error)) throw new Error(`OMP session path has a missing parent: ${current}`);
		throw error;
	}
	const components = resolved.slice(root.length).split(path.sep).filter(Boolean);
	for (const [index, component] of components.entries()) {
		current = path.join(current, component);
		const isLeaf = index === components.length - 1;
		try {
			const stat = fs.lstatSync(current);
			if (stat.isSymbolicLink()) throw new Error(`OMP session path contains a symlink: ${current}`);
			if (!isLeaf && !stat.isDirectory()) throw new Error(`OMP session path parent is not a directory: ${current}`);
		} catch (error) {
			if (isEnoent(error) && isLeaf) return resolved;
			if (isEnoent(error)) throw new Error(`OMP session path has a missing parent: ${current}`);
			throw error;
		}
	}
	return resolved;
}

function sessionReference(value: string, base = sessionsDir): string {
	const candidate = path.isAbsolute(value) ? value : path.join(base, value);
	return safeSessionPath(candidate);
}

function usage(): never {
	console.error(`usage: session_log_usage.ts <session-id | transcript.jsonl | --latest> [--check]`);
	process.exit(2);
}

function finiteNumber(value: unknown): number | undefined {
	if (typeof value === "number" && Number.isFinite(value)) return value;
	if (typeof value === "string" && value.trim() !== "") {
		const parsed = Number(value);
		if (Number.isFinite(parsed)) return parsed;
	}
	return undefined;
}

function nonnegativeInteger(value: unknown): number | undefined {
	const parsed = finiteNumber(value);
	return parsed === undefined ? undefined : Math.max(0, Math.floor(parsed));
}

function nonnegativeCost(value: unknown): number {
	const parsed = finiteNumber(value);
	return parsed === undefined ? 0 : Math.max(0, parsed);
}

function timestampMs(value: unknown): number {
	if (typeof value === "number" && Number.isFinite(value)) return value;
	if (typeof value === "string" && value.trim() !== "") {
		const numeric = Number(value);
		if (Number.isFinite(numeric)) return numeric;
		const parsed = Date.parse(value);
		if (Number.isFinite(parsed)) return parsed;
	}
	return 0;
}

function entryTime(entry: JsonObject, message = entry.message): number {
	return timestampMs(message?.timestamp) || timestampMs(entry.timestamp);
}

function completedTime(entry: JsonObject): number {
	return timestampMs(entry.message?.completedAt) || timestampMs(entry.completedAt) || entryTime(entry);
}

function textOf(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.map(item => {
			if (typeof item === "string") return item;
			return item?.type === "text" && typeof item.text === "string" ? item.text : "";
		})
		.filter(Boolean)
		.join("\n");
}

function promptOf(entry: JsonObject): string | null {
	if (entry.type === "message" && entry.message?.role === "user" && entry.message.attribution !== "agent") {
		return textOf(entry.message.content);
	}
	if (entry.type === "custom_message" && (entry.attribution === "user" || entry.customType === "skill-prompt")) {
		return textOf(entry.content);
	}
	return null;
}

function newUsage(): Usage {
	return { input: 0, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0, total: 0, cost: 0, models: new Set(), efforts: new Set() };
}

function recordedNumber(recorded: JsonObject, names: string[]): number {
	for (const name of names) {
		const value = nonnegativeInteger(recorded[name]);
		if (value !== undefined) return value;
	}
	return 0;
}

function nativeRecordedNumber(recorded: JsonObject, names: string[]): number | undefined {
	for (const name of names) {
		const value = finiteNumber(recorded[name]);
		if (value !== undefined && value >= 0) return Math.floor(value);
	}
	return undefined;
}

function addRecordedUsage(usageValue: Usage, recorded: JsonObject, model: unknown, provider: unknown, effort: unknown): void {
	if (!recorded || typeof recorded !== "object") return;
	const input = recordedNumber(recorded, ["input", "inputTokens", "input_tokens"]);
	const output = recordedNumber(recorded, ["output", "outputTokens", "output_tokens"]);
	const reasoning = recordedNumber(recorded, ["reasoning", "reasoningTokens", "reasoning_tokens"]);
	const cacheRead = recordedNumber(recorded, ["cacheRead", "cacheReadTokens", "cache_read"]);
	const cacheWrite = recordedNumber(recorded, ["cacheWrite", "cacheWriteTokens", "cache_write"]);
	usageValue.input += input;
	usageValue.output += output;
	usageValue.reasoning += reasoning;
	usageValue.cacheRead += cacheRead;
	usageValue.cacheWrite += cacheWrite;
	const total = nativeRecordedNumber(recorded, ["totalTokens", "total_tokens", "total"]);
	usageValue.total += total ?? input + output + reasoning + cacheRead + cacheWrite;
	const cost = recorded.cost;
	usageValue.cost += nonnegativeCost(typeof cost === "object" && cost !== null ? cost.total : cost);
	const modelName = typeof model === "string" ? model : "";
	const providerName = typeof provider === "string" ? provider : "";
	const modelLabel = modelName ? (providerName && !modelName.includes("/") ? `${providerName}/${modelName}` : modelName) : "";
	if (modelLabel) usageValue.models.add(modelLabel);
	if (typeof effort === "string" && effort) usageValue.efforts.add(effort);
}

function addAssistant(usageValue: Usage, message: JsonObject, currentEffort: string): void {
	if (message.role !== "assistant") return;
	const messageEffort = typeof message.thinkingLevel === "string" ? message.thinkingLevel : typeof message.effort === "string" ? message.effort : currentEffort;
	addRecordedUsage(usageValue, message.usage, message.model, message.provider, messageEffort);
}

function addModelUsage(usageValue: Usage, entry: JsonObject, currentEffort: string): void {
	if (entry.type !== "model_usage") return;
	addRecordedUsage(usageValue, entry.usage, entry.model, entry.provider, currentEffort);
}

function mergeUsage(target: Usage, source: Usage): void {
	target.input += source.input;
	target.output += source.output;
	target.reasoning += source.reasoning;
	target.cacheRead += source.cacheRead;
	target.cacheWrite += source.cacheWrite;
	target.total += source.total;
	target.cost += source.cost;
	for (const model of source.models) target.models.add(model);
	for (const effort of source.efforts) target.efforts.add(effort);
}

function readEntries(file: string): JsonObject[] {
	let contents: string;
	try {
		contents = fs.readFileSync(file, "utf8");
	} catch (error) {
		if (isEnoent(error)) return [];
		throw error;
	}
	const entries: JsonObject[] = [];
	for (const line of contents.split("\n")) {
		if (!line.trim()) continue;
		try {
			const value = JSON.parse(line);
			if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("record is not an object");
			entries.push(value as JsonObject);
		} catch {
			// OMP transcripts can be interrupted mid-write; ignore only the malformed line.
		}
	}
	return entries;
}

function sessionHeader(entries: JsonObject[]): JsonObject | null {
	return entries.find(entry => entry.type === "session") ?? null;
}

function isEnoent(error: unknown): boolean {
	if (typeof error !== "object" || error === null || !("code" in error)) return false;
	return error.code === "ENOENT";
}

function walkJsonl(dir: string): string[] {
	const files: string[] = [];
	const safeDir = safeSessionPath(dir);
	let entries: fs.Dirent[];
	try {
		entries = fs.readdirSync(safeDir, { withFileTypes: true });
	} catch (error) {
		if (isEnoent(error)) return files;
		throw error;
	}
	for (const entry of entries) {
		const full = path.join(safeDir, entry.name);
		try {
			if (entry.isSymbolicLink()) throw new Error(`OMP session path contains a symlink: ${full}`);
			if (entry.isDirectory()) files.push(...walkJsonl(full));
			else if (entry.isFile() && entry.name.endsWith(".jsonl")) files.push(safeSessionPath(full));
		} catch (error) {
			if (!isEnoent(error)) throw error;
		}
	}
	return files;
}

function recordFromFile(file: string): SessionRecord | null {
	const resolved = safeSessionPath(file);
	const entries = readEntries(resolved);
	const header = sessionHeader(entries);
	if (!header) return null;
	const id = typeof header.id === "string" ? header.id : path.basename(resolved, ".jsonl");
	return validId(id) ? { file: resolved, header, entries } : null;
}

function loadSessionsFrom(dir: string): SessionRecord[] {
	return walkJsonl(dir).map(recordFromFile).filter((value): value is SessionRecord => value !== null);
}

function loadSessions(): SessionRecord[] {
	return loadSessionsFrom(sessionsDir);
}
function sessionId(record: SessionRecord): string {
	const value = typeof record.header.id === "string" ? record.header.id : path.basename(record.file, ".jsonl");
	return validId(value) ? value : "";
}

function parentFile(record: SessionRecord, byId: Map<string, SessionRecord>): string | null {
	const parent = record.header.parentSession;
	if (typeof parent !== "string" || !parent) return null;
	const bySessionId = [...byId.values()].find(candidate => sessionId(candidate) === parent);
	if (bySessionId) return bySessionId.file;
	let resolved: string;
	try { resolved = sessionReference(parent); } catch { return null; }
	return byId.has(resolved) ? resolved : null;
}

function rootFile(record: SessionRecord, byId: Map<string, SessionRecord>): string {
	let current = record;
	const seen = new Set<string>();
	while (true) {
		if (seen.has(current.file)) throw new Error(`Malformed OMP session ancestry cycle involving ${current.file}`);
		seen.add(current.file);
		const hasParent = typeof current.header.parentSession === "string" && current.header.parentSession.length > 0;
		const parent = parentFile(current, byId);
		if (hasParent && !parent) throw new Error(`Malformed OMP session ancestry involving ${current.file}`);
		const next = parent ? byId.get(parent) : undefined;
		if (!next) break;
		current = next;
	}
	return current.file;
}

function hasUnresolvedParent(record: SessionRecord, byId: Map<string, SessionRecord>): boolean {
	const hasParent = typeof record.header.parentSession === "string" && record.header.parentSession.length > 0;
	return hasParent && !parentFile(record, byId);
}

function resolveTarget(target: string, records: SessionRecord[]): SessionRecord {
	if (target !== "--latest" && !validId(target)) {
		let isFile = false;
		let resolved = "";
		try {
			resolved = safeSessionPath(target);
			isFile = fs.statSync(resolved).isFile();
		} catch (error) {
			if (!isEnoent(error)) throw error;
		}
		if (isFile) {
			const record = recordFromFile(resolved);
			if (record) return record;
		}
	}
	const byFile = new Map(records.map(record => [record.file, record]));
	const byId = byFile;
	const malformed = new Set<string>();
	for (const record of records) {
		try { rootFile(record, byFile); } catch { malformed.add(record.file); }
	}
	const roots = records.filter(record =>
		!malformed.has(record.file) &&
		!parentFile(record, byId) &&
		!hasUnresolvedParent(record, byId)
	);
	if (target === "--latest") {
		const cwd = path.resolve(process.cwd());
		const inCwd = roots.filter(record => typeof record.header.cwd === "string" && record.header.cwd.length > 0 && path.resolve(record.header.cwd) === cwd);
		const candidates = inCwd.length ? inCwd : roots;
		const newest = candidates.sort((a, b) =>
			modifiedTime(b) - modifiedTime(a) ||
			timestampMs(b.header.timestamp) - timestampMs(a.header.timestamp) ||
			a.file.localeCompare(b.file),
		)[0];
		if (!newest) throw new Error(`No OMP session found under ${sessionsDir}`);
		return newest;
	}
	if (!validId(target)) throw new Error(`Invalid OMP session target: ${target}`);
	const matches = records.filter(record => sessionId(record) === target || sessionId(record).startsWith(target));
	if (matches.length === 1) {
		if (malformed.has(matches[0].file)) throw new Error(`Malformed OMP session ancestry involving ${matches[0].file}`);
		return matches[0];
	}
	if (matches.length > 1) throw new Error(`Session id is ambiguous: ${matches.map(sessionId).join(", ")}`);
	throw new Error(`No OMP session found for: ${target}`);
}


function modifiedTime(record: SessionRecord): number {
	try { return fs.statSync(record.file).mtimeMs; } catch { return timestampMs(record.header.timestamp); }
}
function cleanHead(value: string): string {
	return value.replace(/\s+/g, " ").slice(0, 60);
}

function formatHms(milliseconds: number): string {
	const seconds = Math.max(0, Math.floor(milliseconds / 1000));
	return [Math.floor(seconds / 3600), Math.floor((seconds % 3600) / 60), seconds % 60].map(value => String(value).padStart(2, "0")).join(":");
}

function formatUsage(value: Usage): string {
	const models = [...value.models].sort().join("+") || "-";
	const efforts = [...value.efforts].sort().join("+") || "-";
	return `est. used token: input: ${value.input}, output: ${value.output}, reasoning: ${value.reasoning}, cache_write: ${value.cacheWrite}, cache_read: ${value.cacheRead}, total_tokens: ${value.total}, cost: $${value.cost.toFixed(4)}, model: ${models}, effort: ${efforts}`;
}

function aggregate(record: SessionRecord): Aggregate {
	const requests: Segment[] = [];
	const helperUsage = newUsage();
	let helpers = 0;
	let current: Segment | null = null;
	let currentEffort = "";
	const latestResponses = new Map<string, number>();
	for (const [index, entry] of record.entries.entries()) {
		if (entry.type !== "message" || entry.message?.role !== "assistant") continue;
		const message = entry.message;
		const identity = message.responseId || message.messageId || message.id;
		const responseKey = ((typeof identity === "string" && identity) || typeof identity === "number")
			? `id:${String(identity)}`
			: typeof message.timestamp === "string" || typeof message.timestamp === "number"
				? `timestamp:${String(message.timestamp)}`
				: "";
		if (responseKey) latestResponses.set(responseKey, index);
	}
	for (const [index, entry] of record.entries.entries()) {
		if (entry.type === "thinking_level_change" && typeof entry.thinkingLevel === "string") currentEffort = entry.thinkingLevel;
		const prompt = promptOf(entry);
		if (prompt !== null) {
			const start = entryTime(entry);
			if (current) { requests.push(current); current = null; }
			current = { prompt, start, end: 0, usage: newUsage() };
		}
		if (entry.type === "model_usage") { helpers += 1; addModelUsage(current?.usage || helperUsage, entry, currentEffort); continue; }
		if (entry.type !== "message" || entry.message?.role !== "assistant") continue;
		const message = entry.message;
		const identity = message.responseId || message.messageId || message.id;
		const responseKey = ((typeof identity === "string" && identity) || typeof identity === "number")
			? `id:${String(identity)}`
			: typeof message.timestamp === "string" || typeof message.timestamp === "number"
				? `timestamp:${String(message.timestamp)}`
				: "";
		if (responseKey && latestResponses.get(responseKey) !== index) continue;
		if (!current) current = { prompt: "", start: entryTime(entry), end: 0, usage: newUsage() };
		current.end = Math.max(current.end, completedTime(entry));
		addAssistant(current.usage, message, currentEffort);
	}
	if (current) requests.push(current);
	const total = newUsage();
	let workMs = 0;
	for (const request of requests) {
		request.end = Math.max(request.end, request.start);
		workMs += request.end - request.start;
		mergeUsage(total, request.usage);
	}
	mergeUsage(total, helperUsage);
	return { requests, usage: total, workMs, helpers };
}

function main(): void {
	const args = process.argv.slice(2);
	let target = "";
	let check = false;
	for (const arg of args) {
		if (arg === "--check") check = true;
		else if (arg === "--latest") target = "--latest";
		else if (arg === "--help" || arg === "-h") usage();
		else if (arg.startsWith("-")) usage();
		else if (target) throw new Error("Only one OMP session target is allowed");
		else target = arg;
	}
	if (!target) target = "--latest";
	let records = loadSessions();
	const selected = resolveTarget(target, records);
	if (!records.some(record => record.file === selected.file)) {
		const discovered = new Map(records.map(record => [record.file, record]));
		for (const record of loadSessionsFrom(path.dirname(selected.file))) discovered.set(record.file, record);
		let parent = selected.header.parentSession;
		while (typeof parent === "string" && parent) {
			let parentPath: string;
			try { parentPath = sessionReference(parent); } catch { break; }
			const parentRecord = recordFromFile(parentPath);
			if (!parentRecord) break;
			discovered.set(parentRecord.file, parentRecord);
			parent = parentRecord.header.parentSession;
		}
		records = [...discovered.values()];
	}
	const byFile = new Map(records.map(record => [record.file, record]));
	const root = byFile.get(rootFile(selected, byFile)) ?? selected;
	const family = records.filter(record => {
		try { return rootFile(record, byFile) === root.file; } catch { return false; }
	}).sort((a, b) => (a.file === root.file ? -1 : b.file === root.file ? 1 : modifiedTime(b) - modifiedTime(a)));
	console.log(`session: ${root.file}${root.header.title ? `  — ${root.header.title}` : ""}`);
	const rootAggregate = aggregate(root);
	for (const [index, request] of rootAggregate.requests.entries()) {
		console.log(`${index + 1}. ${request.start ? new Date(request.start).toTimeString().slice(0, 8) : "00:00:00"} (working time ${formatHms(request.end - request.start)}) "${cleanHead(request.prompt)}"`);
		console.log(formatUsage(request.usage));
	}
	const children = family.filter(record => record.file !== root.file);
	if (rootAggregate.helpers) console.log(`internal helpers: ${rootAggregate.helpers}`);
	const childAggregates = children.map(child => ({ child, aggregate: aggregate(child) }));
	for (const { child, aggregate: childAggregate } of childAggregates) {
		const helperLabel = childAggregate.helpers ? `, internal helpers: ${childAggregate.helpers}` : "";
		console.log(`sub-agent: ${sessionId(child)}, working time: ${formatHms(childAggregate.workMs)}${helperLabel}, jsonl: ${child.file}`);
		console.log(formatUsage(childAggregate.usage));
	}
	const total = newUsage();
	mergeUsage(total, rootAggregate.usage);
	for (const { aggregate: childAggregate } of childAggregates) mergeUsage(total, childAggregate.usage);
	console.log("---");
	console.log(`TOTAL: requests: ${rootAggregate.requests.length}, sub-agents: ${children.length}, working time: ${formatHms(rootAggregate.workMs)}`);
	console.log(formatUsage(total));
	if (check) console.log("check: OMP transcript usage is authoritative; native cost fields are preserved");
}

try { main(); } catch (error) { console.error(error instanceof Error ? error.message : String(error)); process.exit(1); }
