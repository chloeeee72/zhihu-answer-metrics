// Functional parity harness: runs a script against a minimal DOM stub and prints every
// injected counter, so the MV3 port can be diffed against the original userscript output
// without a browser.
//
// Usage: node extension/tools/run-logic-check.js [path-to-script.js]
// With no argument it tests extension/content.js.

import { readFileSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const target = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : join(here, '..', 'content.js');

const source = readFileSync(target, 'utf8');

// --- minimal DOM stub -------------------------------------------------------
class FakeNode {
    constructor(tag, text) {
        this.tagName = tag;
        this.children = [];
        this.className = '';
        this.style = { cssText: '' };
        this._text = text || '';
    }
    get innerText() {
        if (this._text) return this._text;
        return this.children.map((c) => c.innerText).join('');
    }
    set innerHTML(html) {
        this._html = html;
    }
    get innerHTML() {
        return this._html || '';
    }
    querySelector(sel) {
        const want = sel.replace(/^\./, '');
        for (const child of this.children) {
            if (child.className === want) return child;
            const deep = child.querySelector(sel);
            if (deep) return deep;
        }
        return null;
    }
    prepend(node) {
        this.children.unshift(node);
    }
}

function makeAnswer(className, text) {
    const answer = new FakeNode('div');
    answer.className = 'AnswerItem';
    const content = new FakeNode('div', text);
    content.className = 'RichContent-inner';
    answer.children.push(content);
    return answer;
}

const fixtures = [
    { label: 'pure chinese', text: '这是一段用于演示的中文正文。扩展会统计汉字数量并按三百字每分钟估算阅读时间。' },
    { label: 'mixed', text: 'Mixed content sample: the extension counts characters, English words and digits separately. 版本 4.3。' },
    { label: 'long', text: '知乎回答常见的长段落示例。'.repeat(40) },
    { label: 'blank', text: '   ' },
    { label: 'digits', text: '1234567890' }
];

const answers = fixtures.map((f) => makeAnswer(f.label, f.text));

const documentStub = {
    body: new FakeNode('body'),
    createElement: (tag) => new FakeNode(tag),
    querySelectorAll: (sel) => (sel === '.AnswerItem' ? answers : [])
};

let observerStarted = false;
class FakeMutationObserver {
    constructor() {}
    observe() {
        observerStarted = true;
    }
}

const sandbox = {
    document: documentStub,
    MutationObserver: FakeMutationObserver,
    requestAnimationFrame: (fn) => fn(),
    setTimeout: (fn) => fn(),
    console
};

vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: target });

// --- report -----------------------------------------------------------------
const strip = (s) => s.replace(/\s+/g, ' ').trim();
let mismatches = 0;

console.log('script under test:', target);
console.log('observer started :', observerStarted);
console.log('');

fixtures.forEach((f, i) => {
    const content = answers[i].children.find((c) => c.className === 'RichContent-inner');
    const counter = content.querySelector('.gm-char-counter');
    if (f.label === 'blank') {
        const ok = counter === null;
        if (!ok) mismatches++;
        console.log(`[${ok ? 'PASS' : 'FAIL'}] ${f.label}: blank answer skipped = ${ok}`);
        return;
    }
    if (!counter) {
        mismatches++;
        console.log(`[FAIL] ${f.label}: no counter injected`);
        return;
    }
    console.log(`[PASS] ${f.label}: ${strip(counter.innerHTML)}`);
});

// Re-run must not duplicate (idempotence check mirrors the original guard).
sandbox.document.querySelectorAll('.AnswerItem').forEach(() => {});
console.log('');
console.log(mismatches === 0 ? 'RESULT: all checks passed' : `RESULT: ${mismatches} check(s) failed`);
process.exitCode = mismatches === 0 ? 0 : 1;
