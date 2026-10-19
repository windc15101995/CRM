import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
const req=createRequire(import.meta.url);
function component(path,name){const target=new URL('../.test-runtime/'+name+'.cjs',import.meta.url);const output=ts.transpileModule(readFileSync(path,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true}}).outputText;writeFileSync(target,output);const component=req(target.pathname).default;unlinkSync(target);return component;}
const Public=component('app/public-registration.tsx','test-public');
const markup=renderToStaticMarkup(React.createElement(Public,{events:[{id:'one',title:'ZOOM_ONE',program:'one',active:1,starts:'2026-11-01T12:30:00Z'},{id:'six',title:'HIDDEN_SIX',program:'six',active:1,starts:'2026-11-02T12:30:00Z'}],refCode:'ABCDE',busy:false,error:'',onSubmit:async()=>{},onLogin:()=>{}}));
assert.ok(markup.includes('ZOOM_ONE'));assert.ok(!markup.includes('HIDDEN_SIX'));assert.ok(!markup.includes('lp-topics'));assert.ok(!markup.includes('<details'));assert.ok(markup.includes('name="ref"'));assert.ok(markup.includes('name="phone"'));assert.ok(markup.includes('123456'));assert.ok(markup.includes('id="dang-ky-zoom"'));
const Tree=component('app/referral-tree.tsx','test-tree');
const people=[{id:'a',name:'Nhánh A',ref_id:null,code:'AAAAA'},{id:'b',name:'Tầng 2',ref_id:'a',code:'BBBBB'},{id:'c',name:'Tầng 3',ref_id:'b',code:'CCCCC'}];const tree=renderToStaticMarkup(React.createElement(Tree,{people,admin:false,onOpen:()=>{}}));assert.ok(tree.includes('Nhánh A'));assert.ok(tree.includes('Tầng 2'));assert.ok(tree.includes('Tầng 3'));assert.equal((tree.match(/<details/g)||[]).length,3);
// Validate cookie isolation of the actual server route without a browser or live writes.
process.env.HN_SUPABASE_URL='https://supabase.example.test';process.env.HN_SUPABASE_KEY='test-publishable';
const file=new URL('../.test-runtime/test-proxy.mjs',import.meta.url);const src=readFileSync('app/api/system/route.ts','utf8').replace("import { env } from 'cloudflare:workers';","const env=globalThis.testEnv;");writeFileSync(file,ts.transpileModule(src,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText);const {GET,POST}=await import(file.href);unlinkSync(file);
const originalFetch=globalThis.fetch;let captured,calls=0;globalThis.fetch=async(url,options)=>{calls++;captured=JSON.parse(options.body).payload;return new Response(JSON.stringify({ok:true,sessionToken:'new-private-session'}),{headers:{'Content-Type':'application/json'}})};
const login=await POST(new Request('https://site.example.test/api/system',{method:'POST',headers:{origin:'https://site.example.test',cookie:'hn_session=cookie-session','Content-Type':'application/json'},body:JSON.stringify({action:'login',username:'adminsss',password:'example-password',sessionToken:'forged-session'})}));
assert.equal(login.status,200);assert.equal(captured.sessionToken,'cookie-session');assert.equal(captured.username,'adminsss');assert.ok(!('sessionToken' in await login.json()));assert.ok(login.headers.get('set-cookie').includes('HttpOnly'));assert.ok(login.headers.get('set-cookie').includes('Secure'));
const prior=calls;const denied=await POST(new Request('https://site.example.test/api/system',{method:'POST',headers:{origin:'https://other.example.test','Content-Type':'application/json'},body:'{}'}));assert.equal(denied.status,400);assert.equal(calls,prior);
await GET(new Request('https://site.example.test/api/system'));assert.equal(captured.action,'state');assert.equal(captured.sessionToken,'');globalThis.fetch=originalFetch;
console.log('PASS: public Zoom signup, referral field, multilevel tree rendering, server-only session cookie, forged-session override and cross-origin rejection. Run supabase/verify.sql for transactional live database checks.');
