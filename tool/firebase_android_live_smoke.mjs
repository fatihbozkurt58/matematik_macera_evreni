import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { randomUUID, randomBytes } from 'node:crypto';

const projectId='matematik-evreni-dev';
const device='R58NA516Q6X';
const packageId='com.fatihbozkurt.matematik.dev';
if(process.argv[2]!=='--apply') {
  console.log('Dry run: temporary verified synthetic dev account; Android login/cold restart/logout; remove only own test data.');
  process.exit(0);
}
process.env.GOOGLE_CLOUD_QUOTA_PROJECT=projectId;
const token=execFileSync('gcloud',['auth','print-access-token','--quiet'],{encoding:'utf8'}).trim();
const require=createRequire(new URL('../functions/package.json',import.meta.url));
const {initializeApp}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
initializeApp({projectId,credential:{getAccessToken:async()=>({access_token:token,expires_in:3500})}});
const auth=getAuth();
const uid='foundation-device-'+randomUUID();
const email=uid+'@example.invalid';
const password='A1'+randomBytes(16).toString('hex');
const profileUrl=`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${uid}`;
const headers={Authorization:`Bearer ${token}`,'x-goog-user-project':projectId,'Content-Type':'application/json'};
const adb=(...args)=>execFileSync('adb',['-s',device,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
function ui(){
  adb('shell','uiautomator','dump','/sdcard/matematik-live-ui.xml');
  return adb('shell','cat','/sdcard/matematik-live-ui.xml');
}
function nodes(xml){return [...xml.matchAll(/<node\b[^>]*>/g)].map(m=>Object.fromEntries([...m[0].matchAll(/([\w-]+)="([^"]*)"/g)].map(v=>[v[1],v[2]])));}
function tap(node){assert.ok(node,'UI element unavailable');const c=node.bounds.match(/\d+/g).map(Number);adb('shell','input','tap',String(Math.round((c[0]+c[2])/2)),String(Math.round((c[1]+c[3])/2)));}
function named(xml,label){return nodes(xml).find(n=>n['content-desc']===label||n.text===label);}
function waitFor(label){for(let i=0;i<10;i++){const xml=ui();if(named(xml,label))return xml;}throw new Error(`Timed out waiting for ${label}`);}
let created=false;
try{
  await auth.createUser({uid,email,password,emailVerified:true,displayName:'SentetikKaptan'});created=true;
  const response=await fetch(profileUrl,{method:'PATCH',headers,body:JSON.stringify({fields:{nickname:{stringValue:'SentetikKaptan'},grade:{integerValue:'3'},avatarId:{stringValue:'explorer_basic'},schemaVersion:{integerValue:'1'},profileRevision:{integerValue:'1'},registrationStatus:{stringValue:'pendingCompliance'},consentComplianceState:{stringValue:'unverified'}}})});
  assert.ok(response.ok,`Synthetic profile seed HTTP ${response.status}`);
  let xml=ui();
  assert.ok(named(xml,'Giriş yap'),'Refusing to replace a device session. Sign-in screen must already be visible.');
  const fields=nodes(xml).filter(n=>n.class==='android.widget.EditText');
  assert.equal(fields.length,2,'Expected existing login form.');
  tap(fields[0]);adb('shell','input','text',email);
  tap(nodes(ui()).filter(n=>n.class==='android.widget.EditText')[1]);adb('shell','input','text',password);
  adb('shell','input','keyevent','4');
  tap(named(ui(),'Giriş yap'));
  waitFor('Haydi keşfe!');
  console.log('ANDROID LIVE PASS: verified synthetic Auth and own server profile guard.');
  adb('shell','am','force-stop',packageId);
  adb('shell','am','start','-n',`${packageId}/com.fatihbozkurt.matematik.MainActivity`);
  xml=waitFor('Haydi keşfe!');
  console.log('ANDROID LIVE PASS: force-stop/cold start restored same synthetic account without login.');
  tap(named(xml,'Kaşifim'));
  xml=waitFor('Çıkış yap');
  tap(named(xml,'Çıkış yap'));
  waitFor('Hoş geldin');
  assert.equal(nodes(ui()).filter(n=>n.class==='android.widget.EditText').length,2);
  console.log('ANDROID LIVE PASS: logout returned to login.');
}finally{
  if(created){
    const outcomes=await Promise.allSettled([
      fetch(profileUrl,{method:'DELETE',headers}).then(r=>assert.ok(r.ok||r.status===404)),
      auth.deleteUser(uid),
    ]);
    assert.ok(outcomes.every(r=>r.status==='fulfilled'),'Synthetic device cleanup failed.');
    console.log('Temporary Android live-test Auth/profile data cleaned.');
  }
}
