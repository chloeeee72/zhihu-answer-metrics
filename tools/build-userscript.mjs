#!/usr/bin/env node
/**
 * Generates the UserScript distribution from the extension's content script.
 *
 * Source of truth: extension/content.js
 * Output:          userscript/zhihu-answer-metrics.user.js
 *
 * The two distributions must behave identically, so instead of maintaining two copies of
 * the same logic, the UserScript is assembled here: a fresh metadata block plus the exact
 * bytes of content.js. `--check` verifies the checked-in output still matches, which is
 * what CI runs.
 *
 * Usage:
 *   node tools/build-userscript.mjs           write the output
 *   node tools/build-userscript.mjs --check   verify (exit 1 on drift)
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourcePath = join(repoRoot, 'extension', 'content.js');
const manifestPath = join(repoRoot, 'extension', 'manifest.json');
const outPath = join(repoRoot, 'userscript', 'zhihu-answer-metrics.user.js');
const originalPath = join(
    repoRoot,
    'userscript',
    'original',
    'zhihu-answer-metrics-4.2.user.js'
);

const checkMode = process.argv.includes('--check');

const read = (p) => readFileSync(p, 'utf8');
const sha = (s) => createHash('sha256').update(s).digest('hex').slice(0, 12);

const source = read(sourcePath);
const manifest = JSON.parse(read(manifestPath));

if (manifest.manifest_version !== 3) {
    throw new Error('extension/manifest.json is not Manifest V3');
}

if (!source.startsWith('(function ()')) {
    throw new Error('extension/content.js must start with the IIFE wrapper');
}

// --- provenance: the ported body must not drift from the original UserScript --------
// The original file still carries the `// ==UserScript== ... ==/UserScript==` header,
// so compare everything after it.
let originalNote = '';
if (existsSync(originalPath)) {
    const original = read(originalPath);
    const end = original.indexOf('// ==/UserScript==');
    if (end !== -1) {
        const originalBody = original.slice(original.indexOf('\n', end) + 1);
        if (originalBody.trim() !== source.trim()) {
            throw new Error(
                'extension/content.js no longer matches the archived original UserScript body.\n' +
                    'If this is intentional, update userscript/original/ as well so the port stays auditable.'
            );
        }
        originalNote = `ported from the original UserScript, body verified identical (sha256:${sha(source)})`;
    }
}
if (!originalNote) {
    originalNote = `content.js sha256:${sha(source)}`;
}

// --- metadata block -----------------------------------------------------------------
const REPO = 'https://github.com/chloeeee72/zhihu-answer-metrics';
const REPO_RAW = 'https://raw.githubusercontent.com/chloeeee72/zhihu-answer-metrics/main';

const header = `// ==UserScript==
// @name         知乎回答字数统计 | 阅读时间估算
// @namespace    ${REPO}
// @version      ${manifest.version}
// @description  ${manifest.description}
// @match        https://www.zhihu.com/question/*
// @grant        none
// @author       Chloe
// @license      MIT
// @homepageURL  ${REPO}
// @supportURL   ${REPO}/issues
// @downloadURL  ${REPO_RAW}/userscript/zhihu-answer-metrics.user.js
// @updateURL    ${REPO_RAW}/userscript/zhihu-answer-metrics.user.js
// ==/UserScript==

// NOTE: generated file - do not edit.
// Source: extension/content.js (${originalNote})
// Regenerate: node tools/build-userscript.mjs

`;

const output = header + source;

if (checkMode) {
    if (!existsSync(outPath)) {
        console.error(`FAIL: ${outPath} is missing. Run: node tools/build-userscript.mjs`);
        process.exit(1);
    }
    if (read(outPath) !== output) {
        console.error('FAIL: userscript/zhihu-answer-metrics.user.js is stale.');
        console.error('Run: node tools/build-userscript.mjs');
        process.exit(1);
    }
    console.log(`OK: userscript up to date (version ${manifest.version}, content sha256:${sha(source)})`);
    process.exit(0);
}

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, output, 'utf8');
console.log(`wrote ${outPath}`);
console.log(`  version      ${manifest.version}`);
console.log(`  content.js   sha256:${sha(source)} (${source.length} bytes)`);
console.log(`  provenance   ${originalNote}`);
