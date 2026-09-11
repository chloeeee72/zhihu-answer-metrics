#!/usr/bin/env node
/**
 * Packs extension/ into store-package.zip using only Node built-ins (no npm install).
 *
 * The zip contains just what the browser loads: manifest.json, content.js and the four
 * raster icons. Reviewer-facing material (demo/, store/, tools/) is excluded so it cannot
 * be mistaken for extension code.
 *
 * Usage: node tools/pack.mjs
 */

import { readFileSync, writeFileSync, statSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateRawSync } from 'node:zlib';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const extDir = join(repoRoot, 'extension');
const outPath = join(repoRoot, 'store-package.zip');

const FILES = [
    'manifest.json',
    'content.js',
    'icons/icon16.png',
    'icons/icon32.png',
    'icons/icon48.png',
    'icons/icon128.png',
];

// --- minimal zip writer ------------------------------------------------------
// Store in deflate when it actually helps, otherwise fall back to stored (method 0),
// which is what happens with already-compressed PNGs.

const crcTable = (() => {
    const table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        table[n] = c;
    }
    return table;
})();

function crc32(buf) {
    let c = -1;
    for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ -1) >>> 0;
}

function dosDateTime(date) {
    const year = Math.max(date.getFullYear(), 1980);
    const time = (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
    const day = ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
    return { time, day };
}

function buildZip(entries) {
    const localParts = [];
    const centralParts = [];
    let offset = 0;
    const { time, day } = dosDateTime(new Date(2026, 0, 1, 0, 0, 0));

    for (const entry of entries) {
        const nameBuf = Buffer.from(entry.name, 'utf8');
        const data = entry.data;
        const crc = crc32(data);
        const deflated = deflateRawSync(data, { level: 9 });
        const useDeflate = deflated.length < data.length;
        const payload = useDeflate ? deflated : data;
        const method = useDeflate ? 8 : 0;

        const local = Buffer.alloc(30);
        local.writeUInt32LE(0x04034b50, 0);
        local.writeUInt16LE(20, 4); // version needed
        local.writeUInt16LE(0x0800, 6); // UTF-8 filename flag
        local.writeUInt16LE(method, 8);
        local.writeUInt16LE(time, 10);
        local.writeUInt16LE(day, 12);
        local.writeUInt32LE(crc, 14);
        local.writeUInt32LE(payload.length, 18);
        local.writeUInt32LE(data.length, 22);
        local.writeUInt16LE(nameBuf.length, 26);
        local.writeUInt16LE(0, 28);
        localParts.push(local, nameBuf, payload);

        const central = Buffer.alloc(46);
        central.writeUInt32LE(0x02014b50, 0);
        central.writeUInt16LE(20, 4); // version made by
        central.writeUInt16LE(20, 6); // version needed
        central.writeUInt16LE(0x0800, 8);
        central.writeUInt16LE(method, 10);
        central.writeUInt16LE(time, 12);
        central.writeUInt16LE(day, 14);
        central.writeUInt32LE(crc, 16);
        central.writeUInt32LE(payload.length, 20);
        central.writeUInt32LE(data.length, 24);
        central.writeUInt16LE(nameBuf.length, 28);
        central.writeUInt16LE(0, 30); // extra
        central.writeUInt16LE(0, 32); // comment
        central.writeUInt16LE(0, 34); // disk number
        central.writeUInt16LE(0, 36); // internal attrs
        central.writeUInt32LE(0, 38); // external attrs
        central.writeUInt32LE(offset, 42);
        centralParts.push(central, nameBuf);

        offset += local.length + nameBuf.length + payload.length;
    }

    const centralBuf = Buffer.concat(centralParts);
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(0, 4);
    end.writeUInt16LE(0, 6);
    end.writeUInt16LE(entries.length, 8);
    end.writeUInt16LE(entries.length, 10);
    end.writeUInt32LE(centralBuf.length, 12);
    end.writeUInt32LE(offset, 16);
    end.writeUInt16LE(0, 20);

    return Buffer.concat([...localParts, centralBuf, end]);
}

// --- pack ---------------------------------------------------------------------
// The store-facing privacy policy lives once, in docs/privacy.html, so GitHub Pages can
// serve it directly. extension/demo/privacy.html is a generated redirect shim. Refresh it
// here (and in --check) so the two can never drift.
const canonicalPrivacy = join(repoRoot, 'docs', 'privacy.html');
const shimPath = join(extDir, 'demo', 'privacy.html');
const PAGES_URL = 'https://chloeeee72.github.io/zhihu-answer-metrics/privacy.html';

if (!existsSync(canonicalPrivacy)) {
    throw new Error('missing docs/privacy.html - it is the canonical privacy policy');
}

const privacyShim = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>隐私政策已迁移 — 知乎回答字数统计 | 阅读时间估算</title>
<link rel="canonical" href="${PAGES_URL}">
<meta http-equiv="refresh" content="0; url=${PAGES_URL}">
<style>
    body { font: 15px/1.7 -apple-system, "Segoe UI", "Microsoft YaHei", sans-serif; padding: 48px 20px; color: #222; }
    a { color: #056de8; }
    code { background: #f2f2f2; padding: 1px 5px; border-radius: 3px; }
</style>
</head>
<body>
<p>隐私政策的规范版已迁移到：<br>
<a href="${PAGES_URL}">${PAGES_URL}</a></p>
<p>仓库内的规范文件是 <code>docs/privacy.html</code>。本文件只是给指向旧路径的链接留的重定向，
由 <code>tools/pack.mjs</code> 自动生成，请勿手改。</p>
</body>
</html>
`;

if (process.argv.includes('--check')) {
    if (!existsSync(shimPath) || readFileSync(shimPath, 'utf8') !== privacyShim) {
        console.error('FAIL: extension/demo/privacy.html is not the current redirect shim.');
        console.error('Run: node tools/pack.mjs');
        process.exit(1);
    }
    console.log('OK: privacy redirect shim is in sync with docs/privacy.html');
    process.exit(0);
}

writeFileSync(shimPath, privacyShim, 'utf8');
console.log(`refreshed ${shimPath} (redirect -> ${PAGES_URL})`);

const entries = FILES.map((name) => {
    const full = join(extDir, name);
    return { name, data: readFileSync(full), size: statSync(full).size };
});

const zip = buildZip(entries);
writeFileSync(outPath, zip);

console.log(`packed ${outPath} (${zip.length} bytes)`);
for (const e of entries) {
    console.log(`  ${e.name}  ${e.size} bytes`);
}
console.log(`  ${entries.length} files, extension/manifest.json version ${JSON.parse(readFileSync(join(extDir, 'manifest.json'), 'utf8')).version}`);
