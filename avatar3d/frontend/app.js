import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// ---------------------------------------------------------------- constants
const MAX_BYTES = 10 * 1024 * 1024;
const OK_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const POLL_MS = 2000;
const TARGET_HEIGHT = 1.7;
const STAGES = ['queued', 'removing_background', 'stylizing', 'generating_mesh', 'finalizing', 'done'];
// Khronos sample asset; button is only shown if a runtime probe of this URL succeeds.
const SAMPLE_URL = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/CesiumMan/glTF-Binary/CesiumMan.glb';

const $ = (id) => document.getElementById(id);
const el = {
  providerBadge: $('providerBadge'), stylizeBadge: $('stylizeBadge'), warnBanner: $('warnBanner'),
  dropzone: $('dropzone'), fileInput: $('fileInput'), preview: $('preview'), dropHint: $('dropHint'),
  generateBtn: $('generateBtn'), stepper: $('stepper'), jobMsg: $('jobMsg'), jobTime: $('jobTime'),
  errorBox: $('errorBox'), errorText: $('errorText'), retryBtn: $('retryBtn'),
  pauseBtn: $('pauseBtn'), clipBtns: $('clipBtns'), animInfo: $('animInfo'), swayRange: $('swayRange'), speedRange: $('speedRange'),
  openLocalBtn: $('openLocalBtn'), downloadBtn: $('downloadBtn'), sampleBtn: $('sampleBtn'), glbInput: $('glbInput'),
  modelMsg: $('modelMsg'), gallery: $('gallery'), galleryEmpty: $('galleryEmpty'),
  canvas: $('viewer'), viewerMsg: $('viewerMsg'), viewerWrap: $('viewerWrap'),
};

// ---------------------------------------------------------------- viewer
const renderer = new THREE.WebGLRenderer({ canvas: el.canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x2a303b);
scene.fog = new THREE.Fog(0x2a303b, 8, 25);

const camera = new THREE.PerspectiveCamera(40, 1, 0.05, 100);
camera.position.set(0, 1.3, 4);

const controls = new OrbitControls(camera, el.canvas);
controls.target.set(0, TARGET_HEIGHT / 2, 0);
controls.enableDamping = true;
controls.maxPolarAngle = Math.PI * 0.495;
controls.update();

scene.add(new THREE.HemisphereLight(0xdfe8ff, 0x444455, 1.1));
const sun = new THREE.DirectionalLight(0xffffff, 2.2);
sun.position.set(2.5, 5, 3);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -2.5, right: 2.5, top: 3, bottom: -2, near: 0.5, far: 15 });
sun.shadow.radius = 5;
sun.shadow.bias = -0.0004;
scene.add(sun);

const ground = new THREE.Mesh(new THREE.CircleGeometry(6, 64), new THREE.ShadowMaterial({ opacity: 0.35 }));
ground.rotation.x = -Math.PI / 2;
ground.receiveShadow = true;
scene.add(ground);
const disc = new THREE.Mesh(new THREE.CircleGeometry(6, 64), new THREE.MeshBasicMaterial({ color: 0x343b48 }));
disc.rotation.x = -Math.PI / 2;
disc.position.y = -0.002;
scene.add(disc);

function resize() {
  const w = el.viewerWrap.clientWidth, h = el.viewerWrap.clientHeight;
  if (!w || !h) return;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
new ResizeObserver(resize).observe(el.viewerWrap);
resize();

// wrapper group pivots at the feet (origin, y=0); procedural motion is applied to it
const wrapper = new THREE.Group();
scene.add(wrapper);

const loader = new GLTFLoader();
let currentRoot = null;
let mixer = null;
let hasClips = false;
let idleAction = null;
let busyAction = null;
let paused = false;
let phaseB = 0, phaseS = 0, bobPhase = 0; // accumulated phases (so slider changes never snap)
let current = { id: null, url: null, name: 'avatar.glb', blobUrl: null };

function disposeCurrent() {
  if (mixer) { mixer.stopAllAction(); mixer = null; }
  idleAction = null; busyAction = null;
  if (el.clipBtns) { el.clipBtns.innerHTML = ''; el.clipBtns.hidden = true; }
  if (currentRoot) {
    wrapper.remove(currentRoot);
    currentRoot.traverse((o) => {
      if (o.isMesh) {
        o.geometry?.dispose();
        for (const m of [].concat(o.material || [])) {
          for (const k in m) if (m[k]?.isTexture) m[k].dispose();
          m.dispose();
        }
      }
    });
    currentRoot = null;
  }
  resetWrapper();
}

function resetWrapper() {
  wrapper.scale.set(1, 1, 1);
  wrapper.rotation.set(0, 0, 0);
  wrapper.position.set(0, 0, 0);
}

function applyDefaultMaterials(root) {
  root.traverse((o) => {
    if (!o.isMesh) return;
    o.castShadow = true;
    o.receiveShadow = false;
    const hasColors = !!o.geometry.attributes.color;
    const mats = [].concat(o.material || []);
    if (!mats.length) {
      o.material = new THREE.MeshStandardMaterial({ color: 0xb8c4d6, roughness: 0.6, metalness: 0.05, vertexColors: hasColors });
      return;
    }
    for (const m of mats) {
      if (m.map) continue;
      if (hasColors) { m.vertexColors = true; m.needsUpdate = true; continue; }
      if (m.color && m.color.getHex() === 0xffffff && !m.emissiveMap) {
        m.color.set(0xb8c4d6);
        if ('roughness' in m) { m.roughness = 0.6; m.metalness = Math.min(m.metalness ?? 0, 0.1); }
        m.needsUpdate = true;
      }
    }
  });
}

function frameModel(root) {
  root.updateMatrixWorld(true);
  let box = new THREE.Box3().setFromObject(root);
  const size = box.getSize(new THREE.Vector3());
  if (!isFinite(size.y) || size.y <= 0) return;
  const s = TARGET_HEIGHT / size.y;
  root.scale.multiplyScalar(s);
  root.updateMatrixWorld(true);
  box = new THREE.Box3().setFromObject(root);
  const c = box.getCenter(new THREE.Vector3());
  root.position.x -= c.x;
  root.position.z -= c.z;
  root.position.y -= box.min.y; // feet at y=0
  root.updateMatrixWorld(true);
}

function showModel(gltf, name) {
  disposeCurrent();
  const root = gltf.scene;
  applyDefaultMaterials(root);
  frameModel(root);
  wrapper.add(root);
  currentRoot = root;

  hasClips = gltf.animations && gltf.animations.length > 0;
  if (hasClips) {
    const clip = gltf.animations.find((c) => /idle/i.test(c.name)) || gltf.animations[0];
    mixer = new THREE.AnimationMixer(root);
    const action = mixer.clipAction(clip);
    action.setLoop(THREE.LoopRepeat, Infinity);
    action.play();
    idleAction = action;
    el.animInfo.textContent = `Clip: ${clip.name || '(unnamed)'}`;
    setupActionButtons(gltf.animations.filter((c) => c !== clip));
  } else {
    el.animInfo.textContent = 'Procedural idle';
  }
  el.viewerMsg.classList.add('hidden');
  el.downloadBtn.disabled = false;
  el.modelMsg.textContent = name;
}

// One-shot clips (wave, dance, ...): crossfade idle -> clip, then back to idle when it ends.
function setupActionButtons(clips) {
  if (!clips.length || !el.clipBtns) return;
  for (const clip of clips) {
    const b = document.createElement('button');
    b.textContent = clip.name ? clip.name[0].toUpperCase() + clip.name.slice(1) : 'Play';
    b.addEventListener('click', () => playOnce(clip));
    el.clipBtns.appendChild(b);
  }
  el.clipBtns.hidden = false;
  mixer.addEventListener('finished', (e) => {
    if (e.action !== busyAction) return;
    busyAction = null;
    e.action.fadeOut(0.4);
    idleAction.reset().fadeIn(0.4).play();
    setActionButtonsDisabled(false);
  });
}

function setActionButtonsDisabled(v) {
  el.clipBtns?.querySelectorAll('button').forEach((b) => { b.disabled = v; });
}

function playOnce(clip) {
  if (!mixer || !idleAction || busyAction) return;
  const a = mixer.clipAction(clip);
  a.reset();
  a.setLoop(THREE.LoopOnce, 1);
  a.clampWhenFinished = true;
  a.play();
  idleAction.fadeOut(0.4);
  a.fadeIn(0.4);
  busyAction = a;
  setActionButtonsDisabled(true);
  if (paused) { paused = false; el.pauseBtn.textContent = 'Pause'; }
}

function loadFromBuffer(buf, name) {
  return new Promise((resolve, reject) => {
    loader.parse(buf, '', (g) => { showModel(g, name); resolve(); }, reject);
  });
}

async function loadFromUrl(url, name) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`Could not download model (HTTP ${r.status})`);
  await loadFromBuffer(await r.arrayBuffer(), name);
}

// animation loop
const clock = new THREE.Clock();
function tick() {
  requestAnimationFrame(tick);
  const dt = Math.min(clock.getDelta(), 0.1);
  if (!paused) {
    const speed = parseFloat(el.speedRange.value);
    if (mixer) mixer.update(dt * speed);
    else if (currentRoot) {
      phaseB += dt * speed;
      phaseS += dt;
      bobPhase += dt * speed;
      const sway = parseFloat(el.swayRange.value);
      const TAU = Math.PI * 2;
      const b = Math.sin(TAU * phaseB / 4);                // breathing, 4 s
      const yawS = Math.sin(TAU * phaseS / 6);             // sway, 6 s
      const rollS = Math.sin(TAU * phaseS / 6 + Math.PI / 2); // out of phase
      const deg = Math.PI / 180;
      wrapper.scale.set(1 - 0.005 * b, 1 + 0.01 * b, 1 - 0.005 * b);
      wrapper.rotation.y = 3 * deg * sway * yawS;
      wrapper.rotation.z = 1 * deg * sway * rollS;
      wrapper.position.y = 0.004 * Math.sin(TAU * bobPhase / 4 + 0.6);
    }
  }
  controls.update();
  renderer.render(scene, camera);
}
tick();

el.pauseBtn.addEventListener('click', () => {
  paused = !paused;
  el.pauseBtn.textContent = paused ? 'Play' : 'Pause';
});

// ---------------------------------------------------------------- config
async function loadConfig() {
  try {
    const cfg = await (await fetch('/api/config')).json();
    const provider = cfg.provider || cfg.active_provider || 'unknown';
    el.providerBadge.textContent = `provider: ${provider}`;
    el.warnBanner.hidden = provider !== 'hf_space';
    const stylize = cfg.stylize ?? cfg.stylize_enabled ?? cfg.optional_steps?.stylize ?? cfg.optional_steps?.stylize_enabled;
    el.stylizeBadge.hidden = !stylize;
  } catch {
    el.providerBadge.textContent = 'provider: unavailable';
  }
}

// ---------------------------------------------------------------- upload + job
let selectedFile = null;
let pollTimer = null;
let jobRunToken = 0;

function setFile(file) {
  hideError();
  if (!file) return;
  if (!OK_TYPES.includes(file.type)) return showError('Unsupported file type. Please use a JPG, PNG or WebP image.', false);
  if (file.size > MAX_BYTES) return showError('That file is larger than 10 MB. Please choose a smaller image.', false);
  selectedFile = file;
  if (el.preview.src) URL.revokeObjectURL(el.preview.src);
  el.preview.src = URL.createObjectURL(file);
  el.preview.hidden = false;
  el.dropHint.hidden = true;
  el.generateBtn.disabled = false;
}

el.dropzone.addEventListener('click', () => el.fileInput.click());
el.dropzone.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); el.fileInput.click(); } });
el.fileInput.addEventListener('change', () => { setFile(el.fileInput.files[0]); el.fileInput.value = ''; });
['dragenter', 'dragover'].forEach((t) => el.dropzone.addEventListener(t, (e) => { e.preventDefault(); el.dropzone.classList.add('drag'); }));
['dragleave', 'drop'].forEach((t) => el.dropzone.addEventListener(t, (e) => { e.preventDefault(); el.dropzone.classList.remove('drag'); }));
el.dropzone.addEventListener('drop', (e) => setFile(e.dataTransfer.files[0]));

function showError(text, retryable = true) {
  el.errorText.textContent = text;
  el.retryBtn.hidden = !retryable;
  el.errorBox.hidden = false;
}
function hideError() { el.errorBox.hidden = true; }

function renderStepper(status) {
  el.stepper.hidden = false;
  const idx = STAGES.indexOf(status);
  el.stepper.querySelectorAll('li').forEach((li, i) => {
    li.classList.toggle('done', idx > i || status === 'done');
    li.classList.toggle('active', idx === i && status !== 'done');
  });
}

function stopPolling() { clearTimeout(pollTimer); pollTimer = null; }

function setBusy(busy) {
  el.generateBtn.disabled = busy || !selectedFile;
  el.generateBtn.textContent = busy ? 'Working…' : 'Generate avatar';
}

async function startJob() {
  if (!selectedFile) return;
  stopPolling();
  hideError();
  const token = ++jobRunToken;
  setBusy(true);
  renderStepper('queued');
  el.jobMsg.textContent = 'Uploading…';
  el.jobTime.textContent = '';
  try {
    const fd = new FormData();
    fd.append('photo', selectedFile);
    const r = await fetch('/api/avatars', { method: 'POST', body: fd });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(errText(data) || `Upload failed (HTTP ${r.status})`);
    poll(data.job_id, token, 0);
  } catch (e) {
    setBusy(false);
    el.stepper.hidden = true;
    el.jobMsg.textContent = '';
    showError(e.message || 'Upload failed.');
  }
}

function errText(d) {
  const x = d?.detail ?? d?.error ?? d?.message;
  if (!x) return '';
  return typeof x === 'string' ? x : x.message || JSON.stringify(x);
}

async function poll(jobId, token, failures) {
  if (token !== jobRunToken) return;
  try {
    const r = await fetch(`/api/jobs/${encodeURIComponent(jobId)}`);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const j = await r.json();
    if (token !== jobRunToken) return;
    el.jobMsg.textContent = j.message || '';
    el.jobTime.textContent = typeof j.elapsed_s === 'number' ? `Elapsed: ${j.elapsed_s.toFixed(1)} s` : '';
    if (j.status === 'error') {
      setBusy(false);
      el.stepper.querySelectorAll('li.active').forEach((li) => li.classList.remove('active'));
      return showError(j.error || j.message || 'Generation failed.');
    }
    renderStepper(j.status);
    if (j.status === 'done') {
      setBusy(false);
      if (j.model_url) {
        current = { id: idFromUrl(j.model_url), url: j.model_url, name: 'avatar.glb' };
        try { await loadFromUrl(j.model_url, 'Generated avatar'); } catch (e) { showError(`Model generated but failed to load: ${e.message}`, false); }
      }
      refreshGallery();
      return;
    }
    pollTimer = setTimeout(() => poll(jobId, token, 0), POLL_MS);
  } catch (e) {
    if (failures >= 4) {
      setBusy(false);
      return showError(`Lost contact with the server (${e.message}).`);
    }
    pollTimer = setTimeout(() => poll(jobId, token, failures + 1), POLL_MS);
  }
}

function idFromUrl(u) { return (u.match(/\/([^/]+)\.glb/) || [])[1] || null; }

el.generateBtn.addEventListener('click', startJob);
el.retryBtn.addEventListener('click', startJob);

// ---------------------------------------------------------------- model buttons
el.openLocalBtn.addEventListener('click', () => el.glbInput.click());
el.glbInput.addEventListener('change', async () => {
  const f = el.glbInput.files[0];
  el.glbInput.value = '';
  if (!f) return;
  try {
    const buf = await f.arrayBuffer();
    current = { id: null, url: null, name: f.name, blobUrl: URL.createObjectURL(new Blob([buf], { type: 'model/gltf-binary' })) };
    await loadFromBuffer(buf, `Local: ${f.name}`);
    markGallery();
  } catch (e) {
    el.modelMsg.textContent = `Could not open that file: ${e.message || e}`;
  }
});

el.downloadBtn.addEventListener('click', async () => {
  const href = current.blobUrl || current.url;
  if (!href) return;
  try {
    const r = await fetch(href);
    const blob = await r.blob();
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = current.name || 'avatar.glb';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 5000);
  } catch (e) {
    el.modelMsg.textContent = `Download failed: ${e.message}`;
  }
});

el.sampleBtn.addEventListener('click', async () => {
  el.modelMsg.textContent = 'Loading sample…';
  try {
    current = { id: null, url: SAMPLE_URL, name: 'CesiumMan.glb', blobUrl: null };
    await loadFromUrl(SAMPLE_URL, 'Sample: Khronos CesiumMan (animated)');
    markGallery();
  } catch (e) {
    el.modelMsg.textContent = `Could not load sample: ${e.message}`;
  }
});

// only show the sample button if the URL actually resolves
fetch(SAMPLE_URL, { method: 'HEAD' }).then((r) => { el.sampleBtn.hidden = !r.ok; }).catch(() => {});

// ---------------------------------------------------------------- gallery
async function refreshGallery() {
  let items = [];
  try {
    const r = await fetch('/api/avatars');
    const d = await r.json();
    items = Array.isArray(d) ? d : d.avatars || [];
  } catch { /* leave empty */ }
  el.gallery.replaceChildren();
  el.galleryEmpty.hidden = items.length > 0;
  for (const a of items) {
    const li = document.createElement('li');
    li.dataset.id = a.id;
    const img = document.createElement('img');
    img.className = 'thumb';
    img.alt = '';
    if (a.thumbnail) img.src = a.thumbnail;
    const info = document.createElement('div');
    info.className = 'info';
    const when = a.created_at ? new Date(typeof a.created_at === 'number' && a.created_at < 1e12 ? a.created_at * 1000 : a.created_at) : null;
    const t = document.createElement('span');
    t.textContent = when && !isNaN(when) ? when.toLocaleString() : a.id;
    const s = document.createElement('small');
    s.textContent = a.provider || '';
    info.append(t, s);
    info.title = 'View';
    info.addEventListener('click', () => viewAvatar(a));
    img.addEventListener('click', () => viewAvatar(a));
    const del = document.createElement('button');
    del.textContent = 'Delete';
    del.addEventListener('click', () => deleteAvatar(a));
    li.append(img, info, del);
    el.gallery.append(li);
  }
  markGallery();
}

function markGallery() {
  el.gallery.querySelectorAll('li').forEach((li) => li.classList.toggle('current', li.dataset.id === current.id));
}

async function viewAvatar(a) {
  if (!a.model_url) return;
  try {
    current = { id: a.id, url: a.model_url, name: `${a.id}.glb`, blobUrl: null };
    await loadFromUrl(a.model_url, `Avatar ${a.id}`);
    markGallery();
  } catch (e) {
    el.modelMsg.textContent = `Could not load avatar: ${e.message}`;
  }
}

async function deleteAvatar(a) {
  if (!confirm('Delete this avatar and its photo from disk?')) return;
  try {
    const r = await fetch(`/api/avatars/${encodeURIComponent(a.id)}`, { method: 'DELETE' });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    if (current.id === a.id) {
      disposeCurrent();
      current = { id: null, url: null, name: 'avatar.glb' };
      el.viewerMsg.classList.remove('hidden');
      el.downloadBtn.disabled = true;
      el.modelMsg.textContent = '';
      el.animInfo.textContent = 'No model loaded';
    }
  } catch (e) {
    el.modelMsg.textContent = `Delete failed: ${e.message}`;
  }
  refreshGallery();
}

// ---------------------------------------------------------------- init
loadConfig();
refreshGallery();
