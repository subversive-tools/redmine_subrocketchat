#!/usr/bin/env node
/**
 * Reproducible build script for redmine_subrocketchat frontend bundle.
 *
 * 1. Patches @embeddedchat/react/dist/esm/index.js:
 *    - Exports `useMessageStore` (`Cg`) alongside `EmbeddedChat` so Redmine UI controls can open/close threads directly.
 *    - Adds an "In Rocket.Chat öffnen" action with an expand icon to the ChatHeader kebab menu.
 *    - Strips Markdown/links/newlines from the ChatHeader thread title via `window.__rcFormatThreadTitle`.
 * 2. Bundles `rocketchat_embedded.jsx` into `../assets/javascripts/rocketchat_embedded.js` using esbuild.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ecIndexPath = path.join(__dirname, 'node_modules', '@embeddedchat', 'react', 'dist', 'esm', 'index.js');

if (!fs.existsSync(ecIndexPath)) {
  console.error('Error: node_modules/@embeddedchat/react not found. Run `npm install` in frontend/ first.');
  process.exit(1);
}

let ecCode = fs.readFileSync(ecIndexPath, 'utf8');

// 1. Export useMessageStore (Cg)
if (!ecCode.includes('Cg as useMessageStore')) {
  ecCode = ecCode.replace(
    'export{ws as EmbeddedChat,x as darkTheme,w as defaultTheme};',
    'export{ws as EmbeddedChat,Cg as useMessageStore,x as darkTheme,w as defaultTheme};'
  );
}

// 2. Add "In Rocket.Chat öffnen" item at top of ChatHeader kebab menu
if (!ecCode.includes('id:"openRC"')) {
  ecCode = ecCode.replace(
    '[{...c&&{id:"thread",action:N,iconName:"thread",label:"Threads",visible:!0}},',
    '[{id:"openRC",action:()=>{window.__rcOpenFullClient&&window.__rcOpenFullClient()},iconName:"expand",label:"In Rocket.Chat öffnen",visible:!0},{...c&&{id:"thread",action:N,iconName:"thread",label:"Threads",visible:!0}},'
  );
}

// 3. Clean thread title via window.__rcFormatThreadTitle
if (!ecCode.includes('window.__rcFormatThreadTitle')) {
  ecCode = ecCode.replace(
    'te=Cg(t=>{var e;return null===(e=t.threadMainMessage)||void 0===e?void 0:e.msg}),',
    'te=Cg(t=>{var e;const m=null===(e=t.threadMainMessage)||void 0===e?void 0:e.msg;return window.__rcFormatThreadTitle?window.__rcFormatThreadTitle(m):m}),'
  );
}

// 4. Support Enter key to submit inside TOTP modal input
if (!ecCode.includes('onKeyDown:function(e){"Enter"===e.key&&')) {
  ecCode = ecCode.replace(
    'd(V,{type:"password",onChange:function(e){n(e.target.value)},placeholder:"123456"})',
    'd(V,{type:"password",onChange:function(e){n(e.target.value)},onKeyDown:function(e){"Enter"===e.key&&(e.preventDefault(),null!==i&&null!==f&&c(f,i,l),n(void 0))},placeholder:"123456"})'
  );
}

fs.writeFileSync(ecIndexPath, ecCode, 'utf8');
console.log('✔ Patched @embeddedchat/react/dist/esm/index.js');

const outFile = path.resolve(__dirname, '..', 'assets', 'javascripts', 'rocketchat_embedded.js');
const entryFile = path.resolve(__dirname, 'rocketchat_embedded.jsx');
const esbuildBin = path.join(__dirname, 'node_modules', '.bin', 'esbuild');

execFileSync(
  esbuildBin,
  [
    entryFile,
    '--bundle',
    '--minify',
    '--format=iife',
    '--target=es2020',
    '--define:process.env.NODE_ENV="production"',
    '--define:process.env={}',
    `--outfile=${outFile}`,
  ],
  { stdio: 'inherit' }
);

console.log(`✔ Built ${outFile}`);
