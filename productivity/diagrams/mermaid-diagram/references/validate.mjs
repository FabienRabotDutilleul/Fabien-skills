// Headless parse check for Mermaid blocks.
// Usage: node validate.mjs <file.md | file.mmd>
//   .md  — extracts and checks every ```mermaid block
//   else — checks the whole file as one diagram
import { JSDOM } from 'jsdom';
import { readFileSync } from 'fs';

const dom = new JSDOM('<!DOCTYPE html><body></body>', { pretendToBeVisual: true });
global.window = dom.window;
global.document = dom.window.document;
Object.defineProperty(global, 'navigator', { value: dom.window.navigator, configurable: true });
global.DOMPurify = { sanitize: (x) => x, addHook: () => {} };

const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false });

const path = process.argv[2];
if (!path) {
  console.error('usage: node validate.mjs <file.md | file.mmd>');
  process.exit(2);
}
const src = readFileSync(path, 'utf8');

const blocks = path.endsWith('.md')
  ? [...src.matchAll(/```mermaid\r?\n([\s\S]*?)```/g)].map((m, i) => ({ label: `block ${i + 1}`, code: m[1] }))
  : [{ label: path, code: src }];

if (blocks.length === 0) {
  console.error(`no \`\`\`mermaid blocks found in ${path}`);
  process.exit(2);
}

let failed = 0;
for (const { label, code } of blocks) {
  try {
    const res = await mermaid.parse(code);
    console.log(`OK   ${label} (${res.diagramType})`);
  } catch (e) {
    failed++;
    console.error(`FAIL ${label}: ${e.message.split('\n').slice(0, 3).join(' | ')}`);
  }
}
process.exit(failed ? 1 : 0);
