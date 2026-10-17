import { execFileSync } from 'node:child_process';

const projectId = 'matematik-evreni-dev';
const bucket = 'matematik-evreni-dev.firebasestorage.app';
const documentId = 'firebaseConnection';
const objectName = 'dev-diagnostics/firebase-connection.txt';
const apply = process.argv.includes('--apply');

if (process.argv.some((argument) => argument.startsWith('--') && argument !== '--apply')) {
  throw new Error('Only --apply is supported.');
}

console.log(`Project: ${projectId}`);
console.log(`Firestore: devDiagnostics/${documentId}`);
console.log(`Storage: gs://${bucket}/${objectName}`);
if (!apply) {
  console.log('Dry run. Pass --apply to write and verify the dev probe.');
  process.exit(0);
}

const token = execFileSync('gcloud', ['auth', 'print-access-token', '--quiet'], {
  encoding: 'utf8',
}).trim();
if (!token) throw new Error('No gcloud user access token available.');

async function request(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, ...options.headers },
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`${response.status} ${response.statusText}: ${body.slice(0, 500)}`);
  }
  return response.json();
}

const checkedAt = new Date().toISOString();
const storageUrl = new URL(
  `https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o`,
);
storageUrl.searchParams.set('uploadType', 'media');
storageUrl.searchParams.set('name', objectName);
const object = await request(storageUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  body: `Matematik Evreni dev connection probe: ${checkedAt}\n`,
});
if (object.bucket !== bucket || object.name !== objectName) {
  throw new Error('Storage returned an unexpected object identity.');
}

const documentUrl =
  `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)` +
  `/documents/devDiagnostics/${documentId}`;
const document = await request(documentUrl, {
  method: 'PATCH',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    fields: {
      checkedAt: { timestampValue: checkedAt },
      storageObject: { stringValue: objectName },
      kind: { stringValue: 'dev-connectivity-only' },
    },
  }),
});
if (!document.name.endsWith(`/devDiagnostics/${documentId}`)) {
  throw new Error('Firestore returned an unexpected document identity.');
}

const [verifiedDocument, verifiedObject] = await Promise.all([
  request(documentUrl),
  request(
    `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(objectName)}`,
  ),
]);
if (
  verifiedDocument.fields?.storageObject?.stringValue !== objectName ||
  verifiedObject.name !== objectName
) {
  throw new Error('Read-back verification failed.');
}
console.log(`Verified Firestore and Storage dev writes at ${checkedAt}.`);
