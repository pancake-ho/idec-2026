'use strict';
/* Real local MP4 representations, simple simulated-bandwidth selection policy.
   No network shaping, throughput measurement, or trained CNN inference. */
const $ = id => document.getElementById(id);
const hero = $('hero');
const previews = [$('cmp0'), $('cmp1'), $('cmp2')];
const cropViews = [$('crop0'), $('crop1'), $('crop2')];
const state = {
  manifest: null, ready: [], active: null, mode: 'manual',
  budget: 2000, pending: null, pendingAt: null, switching: 0,
  wantPlay: false, time: 120.5, compare: false, comparisonReps: [],
  point: { x: 0.50, y: 0.50 }, lastCrop: 0,
};

function report(message, error = false) {
  $('status').textContent = message;
  $('status').style.color = error ? '#ff9d98' : '#a7bbca';
}
function clamp(x, min, max) { return Math.max(min, Math.min(max, x)); }
function fmtTime(t) {
  if (!Number.isFinite(t)) return '--:--';
  const ticks = Math.round(Math.max(0, t) * 100);
  const mins = Math.floor(ticks / 6000);
  const secs = Math.floor((ticks % 6000) / 100);
  const cent = ticks % 100;
  return String(mins).padStart(2, '0') + ':' + String(secs).padStart(2, '0') + '.' + String(cent).padStart(2, '0');
}
function fmtBitrate(kbps) { return kbps >= 1000 ? (kbps / 1000).toFixed(2) + ' Mbps' : Math.round(kbps) + ' kbps'; }
function repLabel(rep) { return `${fmtBitrate(rep.kbps)} · ${rep.width}×${rep.height}`; }
function closest(target) { return [...state.ready].sort((a, b) => Math.abs(a.bandwidth - target) - Math.abs(b.bandwidth - target))[0]; }
function activeRep() { return state.ready.find(r => r.index === state.active); }
function recommendedRep() {
  const ceiling = state.budget * 1000 * 0.8;
  const affordable = state.ready.filter(r => r.bandwidth <= ceiling);
  return affordable.length ? affordable[affordable.length - 1] : state.ready[0];
}
function setMode(mode) {
  state.mode = mode;
  document.querySelectorAll('.mode').forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
  $('metricMode').textContent = mode === 'auto' ? 'Auto / budget' : 'Manual';
  refreshBudget();
  if (mode === 'manual') { state.pending = null; state.pendingAt = null; }
  if (mode === 'auto') queueAutoChoice();
}
function refreshBudget() {
  $('budgetValue').textContent = fmtBitrate(state.budget);
  $('budgetBar').style.width = (state.budget / Number($('budget').max) * 100).toFixed(1) + '%';
  $('recommended').textContent = state.ready.length ? repLabel(recommendedRep()) : '--';
  const pending = state.ready.find(r => r.index === state.pending);
  $('pending').textContent = pending ? `${fmtBitrate(pending.kbps)} @ ${state.pendingAt.toFixed(1)}s` : '없음';
}
function refreshActive() {
  const rep = activeRep();
  if (!rep) return;
  $('overlayLabel').textContent = fmtBitrate(rep.kbps);
  $('overlaySize').textContent = `${rep.width} × ${rep.height}`;
  $('qualityNow').textContent = 'REAL MP4 · REP ' + String(rep.index).padStart(2, '0');
  $('metricBitrate').textContent = fmtBitrate(rep.kbps);
  $('metricResolution').textContent = `${rep.width} × ${rep.height}`;
  $('representation').value = String(rep.index);
  $('representationNum').textContent = `rep_${String(rep.index).padStart(2, '0')}.mp4`;
  refreshBudget();
}
function updateClock() {
  const duration = (Number.isFinite(hero.duration) && hero.duration > 0) ? hero.duration : state.manifest.duration;
  const current = hero.readyState > 0 && Number.isFinite(hero.currentTime) ? hero.currentTime : state.time;
  state.time = current;
  $('seek').max = Math.max(0, duration - 0.05);
  if (!$('seek').matches(':active')) $('seek').value = Math.min(current, Number($('seek').max));
  $('currentTime').textContent = fmtTime(current);
  $('totalTime').textContent = fmtTime(duration);
  $('metricPosition').textContent = fmtTime(current);
  $('playText').textContent = hero.paused ? '▶ 재생' : 'Ⅱ 일시정지';
}
function safePlay(video) { return video.play().catch(() => { if (video === hero) report('브라우저가 자동 재생을 차단했습니다. 재생 버튼을 한 번 눌러주세요.', true); }); }
function switchTo(rep, reason = 'Manual selection') {
  if (!rep || (state.active === rep.index && hero.getAttribute('src') === rep.url)) return;
  const t = hero.readyState > 0 && Number.isFinite(hero.currentTime) ? hero.currentTime : state.time;
  const shouldResume = !hero.paused || state.wantPlay;
  const token = ++state.switching;
  state.active = rep.index;
  state.pending = null;
  state.pendingAt = null;
  state.wantPlay = shouldResume;
  hero.pause();
  hero.src = rep.url;
  hero.load();
  hero.onloadedmetadata = () => {
    if (token !== state.switching) return;
    const target = clamp(t, 0, Math.max(0, hero.duration - 0.15));
    hero.currentTime = target;
    hero.playbackRate = Number($('speed').value);
    if (shouldResume) safePlay(hero);
    state.wantPlay = false;
    updateClock();
    syncPreviews(true);
  };
  refreshActive();
  report(`${reason}: ${repLabel(rep)} (재생 시점 ${fmtTime(t)} 유지)`);
}
function queueAutoChoice() {
  if (state.mode !== 'auto' || !state.ready.length) return;
  const wanted = recommendedRep();
  if (wanted.index === state.active) {
    state.pending = null; state.pendingAt = null;
  } else if (hero.paused || hero.readyState < 1) {
    switchTo(wanted, 'Auto budget');
  } else {
    const t = hero.currentTime;
    state.pending = wanted.index;
    state.pendingAt = Math.ceil((t + 0.01) / state.manifest.segmentSeconds) * state.manifest.segmentSeconds;
    report(`Auto: ${fmtBitrate(state.budget)} 예산 기준 ${repLabel(wanted)} 선택, ${state.pendingAt.toFixed(1)}s 시점에 전환 예정`);
  }
  refreshBudget();
}
function processPending() {
  if (state.pending === null || state.pendingAt === null || hero.paused) return;
  if (hero.currentTime + 0.05 >= state.pendingAt) {
    const next = state.ready.find(r => r.index === state.pending);
    if (next) switchTo(next, 'Auto budget · nominal 2s boundary');
  }
}
function seekTo(t) {
  const duration = hero.duration || state.manifest.duration;
  const pos = clamp(t, 0, Math.max(0, duration - 0.1));
  state.time = pos;
  if (hero.readyState > 0) hero.currentTime = pos;
  syncPreviews(true);
  if (state.mode === 'auto') queueAutoChoice();
  updateClock();
}
function setComparison(enabled) {
  state.compare = enabled;
  $('compareSection').hidden = !enabled;
  $('compareToggle').checked = enabled;
  if (!enabled) {
    previews.forEach(v => { v.pause(); v.removeAttribute('src'); v.load(); });
    return;
  }
  const choices = [131087, 595491, 3078587];
  state.comparisonReps = choices.map(closest);
  previews.forEach((v, i) => {
    const rep = state.comparisonReps[i];
    $('cmp' + i + 'label').textContent = repLabel(rep);
    v.src = rep.url;
    v.playbackRate = hero.playbackRate;
    v.load();
    v.onloadedmetadata = () => {
      if (!state.compare) return;
      v.currentTime = clamp(state.time, 0, Math.max(0, v.duration - 0.1));
      if (!hero.paused) safePlay(v);
    };
  });
  const unique = new Set(state.comparisonReps.map(r => r.index));
  $('compareNote').textContent = unique.size < 3
      ? '일부 목표 비트레이트가 없어 가까운 표현본을 재사용합니다.'
      : '세 영상은 재생 시점을 주기적으로 보정합니다.';
  requestAnimationFrame(drawCrops);
}
function syncPreviews(force = false) {
  if (!state.compare || hero.readyState < 1) return;
  for (const v of previews) {
    if (v.readyState < 1) continue;
    if (force || Math.abs(v.currentTime - hero.currentTime) > 0.27)
      v.currentTime = clamp(hero.currentTime, 0, Math.max(0, v.duration - 0.1));
    v.playbackRate = hero.playbackRate;
    if (hero.paused) { if (!v.paused) v.pause(); }
    else if (v.paused) safePlay(v);
  }
}
function setCropPoint(video, event) {
  if (!state.compare) setComparison(true);
  if (!video.videoWidth || !video.videoHeight) return;
  const box = video.getBoundingClientRect();
  const ratio = Math.min(box.width / video.videoWidth, box.height / video.videoHeight);
  const w = video.videoWidth * ratio, h = video.videoHeight * ratio;
  const left = box.left + (box.width - w) / 2, top = box.top + (box.height - h) / 2;
  state.point.x = clamp((event.clientX - left) / w, 0, 1);
  state.point.y = clamp((event.clientY - top) / h, 0, 1);
  $('zoomCoords').textContent = `선택 위치: ${(state.point.x * 100).toFixed(1)}% × ${(state.point.y * 100).toFixed(1)}%`;
  drawCrops();
}
function drawCrops() {
  if (!state.compare) return;
  cropViews.forEach((c, i) => {
    const context = c.getContext('2d');
    context.fillStyle = '#070e17';
    context.fillRect(0, 0, c.width, c.height);
    const v = previews[i];
    if (v.readyState < 2 || !v.videoWidth) {
      context.fillStyle = '#a6bbc7'; context.font = '20px sans-serif';
      context.fillText('Video loading…', 18, 40);
      return;
    }
    const cropW = v.videoWidth * 0.14, cropH = v.videoHeight * 0.14;
    const x = clamp(v.videoWidth * state.point.x - cropW / 2, 0, v.videoWidth - cropW);
    const y = clamp(v.videoHeight * state.point.y - cropH / 2, 0, v.videoHeight - cropH);
    try { context.drawImage(v, x, y, cropW, cropH, 0, 0, c.width, c.height); }
    catch (e) { /* Decoded frame may not be available during seek */ }
  });
}
function bindHandlers() {
  $('playPause').addEventListener('click', () => {
    if (hero.paused) safePlay(hero);
    else hero.pause();
  });
  $('backward').addEventListener('click', () => seekTo(state.time - 2));
  $('forward').addEventListener('click', () => seekTo(state.time + 2));
  $('seek').addEventListener('input', e => { $('currentTime').textContent = fmtTime(Number(e.target.value)); });
  $('seek').addEventListener('change', e => seekTo(Number(e.target.value)));
  $('speed').addEventListener('change', e => { hero.playbackRate = Number(e.target.value); syncPreviews(); });
  document.querySelectorAll('[data-mode]').forEach(b => b.addEventListener('click', () => setMode(b.dataset.mode)));
  $('representation').addEventListener('change', e => {
    setMode('manual');
    switchTo(state.ready.find(r => r.index === Number(e.target.value)), 'Manual selection');
  });
  [['presetLow', 131087], ['presetMid', 595491], ['presetHigh', 3078587]].forEach(([id, bw]) => {
    $(id).addEventListener('click', () => { setMode('manual'); switchTo(closest(bw), 'Preset selection'); });
  });
  $('budget').addEventListener('input', e => {
    state.budget = Number(e.target.value);
    if (state.mode !== 'auto') setMode('auto');
    else queueAutoChoice();
  });
  $('compareToggle').addEventListener('change', e => setComparison(e.target.checked));
  [hero, ...previews].forEach(v => v.addEventListener('click', e => setCropPoint(v, e)));
  hero.addEventListener('timeupdate', () => { updateClock(); processPending(); });
  hero.addEventListener('play', () => { updateClock(); syncPreviews(); });
  hero.addEventListener('pause', () => { updateClock(); syncPreviews(); });
  hero.addEventListener('seeked', () => { updateClock(); syncPreviews(true); drawCrops(); });
  hero.addEventListener('ended', () => { syncPreviews(); updateClock(); });
  hero.addEventListener('error', () => {
    report('영상 디코딩/로드 실패: 실제 MP4가 완전히 다운로드되었는지와 브라우저 H.264 지원 여부를 확인하세요.', true);
  });
  document.addEventListener('keydown', e => {
    if (e.code === 'Space' && !['INPUT','SELECT','BUTTON','TEXTAREA'].includes(document.activeElement.tagName)) {
      e.preventDefault(); $('playPause').click();
    }
  });
  setInterval(() => {
    if (state.compare && !hero.paused) syncPreviews();
    if (state.compare && performance.now() - state.lastCrop > 330) { drawCrops(); state.lastCrop = performance.now(); }
  }, 220);
}
async function start() {
  bindHandlers();
  try {
    const response = await fetch('/api/manifest', { cache: 'no-store' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    state.manifest = await response.json();
    state.ready = state.manifest.representations.filter(r => r.available);
    $('connection').textContent = `${state.ready.length}/${state.manifest.representations.length} 표현본 준비`;
    if (state.ready.length === 0) throw new Error('서버에 완전히 다운로드된 BBB MP4가 없습니다. README의 --check를 실행하세요.');
    $('representation').replaceChildren(...state.ready.map(r => {
      const opt = document.createElement('option');
      opt.value = r.index; opt.textContent = `rep_${String(r.index).padStart(2, '0')}  |  ${repLabel(r)}`; return opt;
    }));
    const params = new URLSearchParams(location.search);
    const requestedTime = Number(params.get('t'));
    if (params.has('t') && Number.isFinite(requestedTime)) state.time = clamp(requestedTime, 0, state.manifest.duration - 1);
    const mid = closest(595491);
    switchTo(mid, '실제 BBB 로딩');
    updateClock();
  } catch (e) {
    $('connection').textContent = '미디어 연결 실패';
    report('초기화 실패: ' + e.message, true);
    console.error(e);
  }
}
start();
