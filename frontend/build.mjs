#!/usr/bin/env node
/**
 * Reproducible build script for redmine_subrocketchat frontend bundle.
 *
 * 1. Patches @embeddedchat/react/dist/esm/index.js:
 *    - Exports `useMessageStore` (`Cg`), `useUserStore` (`sg`), `useLoginStore` (`mg`), and `useTotpStore` (`dg`).
 *    - Adds an "In Rocket.Chat öffnen" action with an expand icon to the ChatHeader kebab menu.
 *    - Strips Markdown/links/newlines from the ChatHeader thread title via `window.__rcFormatThreadTitle`.
 *    - Supports `Enter` key submission inside the TOTP modal input.
 *    - Hides the unauthenticated bottom `ChatInput` bar (`"Sign in to chat"` / `"JOIN"`) via `display: "none"` while keeping its ref mounted.
 *    - Fixes EmbeddedChat 0.2.3 + React 18.3.1 infinite re-render loops (`React error #301`) by using shallow equality in Zustand's `useSyncExternalStoreWithSelector` wrapper and removing the redundant `setConfig(props)` `useEffect` in `EmbeddedChat`.
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

// 1. Export useMessageStore (Cg), useUserStore (sg), useLoginStore (mg), and useTotpStore (dg)
if (!ecCode.includes('sg as useUserStore')) {
  ecCode = ecCode.replace(
    /export\{ws as EmbeddedChat[^}]*\};/,
    'export{ws as EmbeddedChat,Cg as useMessageStore,sg as useUserStore,mg as useLoginStore,dg as useTotpStore};'
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

// 5. Revert any inline style patch on ChatInput (`le` is a `useState` setter inside ChatInput, NOT `_objectSpread2`!)
ecCode = ecCode.replace(
  'return d(Z,{className:"ec-chat-input ".concat(I),style:le({},l,!oe&&{display:"none"})}',
  'return d(Z,{className:"ec-chat-input ".concat(I),style:l}'
);
ecCode = ecCode.replace(
  'return!oe?null:d(Z,{className:"ec-chat-input ".concat(I),style:l}',
  'return d(Z,{className:"ec-chat-input ".concat(I),style:l}'
);

// 6. Ensure LoginForm uses standard single Zustand selector (opened automatically via RedmineEmbeddedChatApp useEffect)
ecCode = ecCode.replace(
  '__rcModalOpen=mg((function(e){return e.isLoginModalOpen})),__rcIsAuth=sg(function(e){return e.isUserAuthenticated}),__rcIsLoginIn=mg(function(e){return e.isLoginIn}),__rcIsTotp=dg(function(e){return e.isTotpModalOpen}),X=__rcModalOpen||(!__rcIsAuth&&!__rcIsLoginIn&&!__rcIsTotp)',
  'X=mg((function(e){return e.isLoginModalOpen}))'
);

// 7. Fix EmbeddedChat 0.2.3 + React 18.3.1 infinite re-render bug (React error #301):
// a) Remove redundant `useEffect(() => setConfig(props), [props])` at the top of `zs` (EmbeddedChat root component)
ecCode = ecCode.replace(
  'zs=function(e){var g=he(t((function(){return e})),2),c=g[0],I=g[1];a((function(){I(e)}),[e]);',
  'zs=function(e){var g=he(t((function(){return e})),2),c=e,I=g[1];'
);

// b) Default Zustand's equalityFn in `ig` to shallow equality so object-returning selectors in EmbeddedChat never cause infinite re-render loops
if (!ecCode.includes('function __rcShallow(a,b)')) {
  const shallowFn =
    'function __rcShallow(a,b){if(Object.is(a,b))return!0;if("object"!=typeof a||null===a||"object"!=typeof b||null===b)return!1;var k=Object.keys(a);if(k.length!==Object.keys(b).length)return!1;for(var i=0;i<k.length;i++)if(!Object.prototype.hasOwnProperty.call(b,k[i])||!Object.is(a[k[i]],b[k[i]]))return!1;return!0}';
  ecCode = ecCode.replace(
    'var t=Ig(e.subscribe,e.getState,e.getServerState||e.getState,g,c);',
    shallowFn + 'var t=Ig(e.subscribe,e.getState,e.getServerState||e.getState,g,c||__rcShallow);'
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
