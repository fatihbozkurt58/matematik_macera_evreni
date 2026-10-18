import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const projectId='matematik-evreni-dev';
const appPath='projects/1086662773964/apps/1:1086662773964:android:429cd8d2400e93844fc669';
const device='R58NA516Q6X';
if(process.argv[2]!=='--apply') {
  console.log('Dry run: register only the attached SM N970F debug App Check secret in the fixed dev app. No secret is printed or saved.');
  process.exit(0);
}
let log;
try { log=execFileSync('adb',['-s',device,'logcat','-d','-s','DebugAppCheckProvider'],{encoding:'utf8',maxBuffer:4*1024*1024}); }
catch { throw new Error('Cannot read filtered device App Check log.'); }
const lines=log.split('\n').filter(line=>line.includes('DebugAppCheckProvider')&&line.includes('debug secret'));
let token=lines.at(-1)?.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/i)?.[0];
// The SDK logs a generated secret only once. Log rotation must not require
// clearing app data (which would destroy the student's current session).
if(!token) {
  const files=execFileSync('adb',['-s',device,'shell','run-as','com.fatihbozkurt.matematik.dev','ls','shared_prefs'],{encoding:'utf8'}).split('\n');
  const appId=appPath.split('/apps/')[1];
  const key=Buffer.from('[DEFAULT]').toString('base64url')+'+'+Buffer.from(appId).toString('base64url');
  const file=`com.google.firebase.appcheck.debug.store.${key}.xml`;
  if(files.includes(file)) {
    const xml=execFileSync('adb',['-s',device,'shell','run-as','com.fatihbozkurt.matematik.dev','cat',`shared_prefs/${file}`],{encoding:'utf8'});
    token=xml.match(/<string name="[^\"]*">([a-f0-9-]{36})<\/string>/i)?.[1];
  }
}
if(!token) throw new Error('No device debug secret found; start the normal dev app first.');
const config=JSON.parse(readFileSync(new URL('../android/app/src/dev/google-services.json',import.meta.url)));
if(config.project_info.project_id!==projectId) throw new Error('Wrong dev project.');
const apiKey=config.client[0].api_key[0].current_key;
const exchange=()=>fetch(`https://firebaseappcheck.googleapis.com/v1/${appPath}:exchangeDebugToken?key=${apiKey}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({debugToken:token})});
if((await exchange()).ok) {
  console.log('Attached Android debug App Check token already accepted by dev Firebase.');
  process.exit(0);
}
const accessToken=execFileSync('gcloud',['auth','print-access-token','--quiet'],{encoding:'utf8'}).trim();
const label='Codex SM-N970F '+createHash('sha256').update(token).digest('hex').slice(0,8);
const result=await fetch(`https://firebaseappcheck.googleapis.com/v1/${appPath}/debugTokens`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${accessToken}`,'x-goog-user-project':projectId},body:JSON.stringify({displayName:label,token})});
if(!result.ok) throw new Error(`Device debug token registration HTTP ${result.status}`);
if(!(await exchange()).ok) throw new Error('Device debug App Check exchange failed after registration.');
console.log('Attached SM N970F dev debug App Check registration and exchange verified. Secret was not printed or stored.');
