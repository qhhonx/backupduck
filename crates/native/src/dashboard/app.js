"use strict";
const $ = id => document.getElementById(id);
const en = !navigator.language.toLowerCase().startsWith("zh");
const w = en ? {
  brand:"Receiver admin", section:"Workspace", navOverview:"Overview", navTransfers:"Transfers", local:"Private Wi-Fi only", breadcrumb:"Receiver", topLocal:"Local dashboard",
  loginTitle:"Connect to your Pixel", loginHelp:"Find the access code in BackupDuck on your Pixel under Settings → Browser management. It stays the same after restarting.", remember:"Remember this browser for 30 days", logout:"Sign out", code:"10-digit access code", enter:"Open dashboard",
  eyebrow:"PIXEL RECEIVER", title:"Receiver overview", description:"Track files received, added to the phone gallery, and needing attention.", live:"Dashboard connected",
  received:"Received", receivedHint:"Confirmed on this Pixel", published:"Saved to gallery", publishedHint:"Phone media processing complete", waiting:"Waiting", waitingHint:"Received, not yet in gallery", failed:"Failed", failedHint:"Retry from the list below",
  deviceTitle:"Phone status", deviceNote:"Live readings from the Pixel", temperatureLabel:"Battery temperature", batteryLabel:"Battery", freeLabel:"Available space", reservedLabel:"BackupDuck originals", spaceDetail:(total,minimum)=>`Total ${size(total)} · minimum free ${size(minimum)}`, originalsDetail:"Excludes gallery copies", threshold:value=>`Battery pause at ${value} °C`, thermalPaused:"Heat pause active", thermalOff:"Temperature pause is off", waitingReading:"Waiting for reading", charging:"Charging", notCharging:"Not charging", transfers:"Transfer history", tableNote:"Open a file for full details.", retry:"Retry all failed",
  guideTitle:"Status guide", receivingState:"Receiving", waitingState:"Waiting for gallery", failedState:"Gallery processing failed", publishedState:"In phone gallery", guideReceiving:"File is still transferring", guideWaiting:"Received; waiting to join the phone gallery", guidePublished:"In the Pixel gallery; cloud backup is unknown", guideFailed:"Originals remain on the receiver; retry is available",
  state:"Status", kind:"Type", allStates:"All statuses", receiving:"Receiving", processing:"Waiting", publishedFilter:"In gallery", failedFilter:"Failed", allKinds:"All types", photo:"Photo", video:"Video", motion:"Live", burst:"Burst", burstRole:"Burst role", burstPrimary:"Primary frame", burstOther:"Other frame", auto:"Auto refresh", refresh:"Refresh",
  file:"File", status:"Status", captured:"Captured", receivedTime:"Received", publishedTime:"Added to gallery", amount:"Size", perPage:"Per page", jump:"Go to", go:"Go", pagination:"Transfer pages", first:"First page", previous:"Previous page", next:"Next page", last:"Last page", page:n=>`Page ${n}`,
  count:n=>`${n} matching files`, updated:time=>`Updated ${time}`, olderPage:"This page does not auto-refresh", pageSummary:(page,pages,start,end,total)=>`Page ${page} of ${pages} · ${start}–${end} of ${total}`, loading:en?"Loading receiver records…":"正在读取接收端记录…", sessionExpired:en?"Session expired or revoked. Enter the current code from your Pixel.":"会话已失效或被撤销，请输入 Pixel 当前访问码重新登录。", noId:en?"This record has no identifier. Retry it on the Pixel.":"这条记录没有可用标识，请在 Pixel 上重试。", retryError:en?"The receiver could not submit the retry. Try again later; originals are retained.":"接收端未能提交重试。请稍后再试，原件仍保留。", requestSubmitted:en?"Retry submitted. Waiting for updated receiver results.":"重试已提交，等待接收端更新处理结果。", unknown:"—", oldTime:"Not recorded", noCapture:"Unknown", noSender:"Unknown sender", noItems:"No transfers match these filters.",
  loginError:"Check the code on your phone and try again.", locked:"Too many attempts. Try again in five minutes.", connectionError:"Cannot reach your Pixel. Check that receiving and browser management are on.", retried:n=>`${n} failed item(s) queued for retry.`,
  detailTitle:"Transfer details", close:"Close details", senders:"Sending device", progress:"Receive progress", originals:"Originals", error:"Processing note", originalsReceiving:"Still receiving", originalsRetained:"Not cleared from the Pixel", originalsReleased:"Originals cleared from the receiver", conversion:"Enable compatibility conversion on the Pixel, then retry", unsupported:"This media format cannot be processed on the Pixel", burstMpf:"Burst JPEG contains MPF multi-picture metadata", burstExtendedXmp:"Burst JPEG contains extended XMP", burstMultipleXmp:"Burst JPEG contains multiple standard XMP packets", burstXmpConflict:"Burst JPEG already has conflicting burst metadata", burstXmp:"Burst JPEG has unsupported XMP structure", burstStructure:"Burst JPEG has unsupported marker structure", retryHelp:"Try again on the Pixel; if it fails again, check receiver diagnostics", cloud:"Phone gallery completion does not confirm Google Photos cloud backup."
} : {
  brand:"接收端管理", section:"工作台", navOverview:"总览", navTransfers:"传输记录", local:"仅在当前局域网访问", breadcrumb:"接收端", topLocal:"本地管理页",
  loginTitle:"连接你的 Pixel", loginHelp:"在 Pixel 的 BackupDuck「设置 → 浏览器管理」中查看访问码。重启后保持不变。", remember:"记住此浏览器 30 天", logout:"退出登录", code:"10 位访问码", enter:"进入管理页",
  eyebrow:"PIXEL RECEIVER", title:"接收概览", description:"查看接收、加入手机相册和待处理的文件。", live:"已连接管理页",
  received:"已接收", receivedHint:"手机已确认收到的文件", published:"已保存到相册", publishedHint:"Pixel 系统相册处理完成", waiting:"等待处理", waitingHint:"已接收，尚未加入相册", failed:"处理失败", failedHint:"原件保留，可重新处理",
  deviceTitle:"手机状态", deviceNote:"来自接收端的实时读数", temperatureLabel:"电池温度", batteryLabel:"电量", freeLabel:"可用空间", reservedLabel:"BackupDuck 原件", spaceDetail:(total,minimum)=>`总容量 ${size(total)} · 最低可用 ${size(minimum)}`, originalsDetail:"不含相册副本", threshold:value=>`电池达到 ${value} °C 暂停`, thermalPaused:"高温暂停接收", thermalOff:"温控已关闭", waitingReading:"等待读数", charging:"充电中", notCharging:"未充电", transfers:"传输记录", tableNote:"点击文件名查看完整信息。", retry:"重试全部失败项",
  guideTitle:"状态说明", receivingState:"接收中", waitingState:"等待处理", failedState:"处理失败", publishedState:"已保存到相册", guideReceiving:"文件仍在传输", guideWaiting:"已收齐，等待加入手机相册", guidePublished:"已加入 Pixel 相册，云端备份状态未知", guideFailed:"原件仍在接收端，可重试",
  state:"状态", kind:"类型", allStates:"全部状态", receiving:"接收中", processing:"等待处理", publishedFilter:"已保存到相册", failedFilter:"处理失败", allKinds:"全部类型", photo:"照片", video:"视频", motion:"实况", burst:"连拍", burstRole:"连拍角色", burstPrimary:"主照片", burstOther:"组内照片", auto:"自动刷新", refresh:"刷新",
  file:"文件", status:"状态", captured:"拍摄时间", receivedTime:"接收完成", publishedTime:"加入手机相册", amount:"大小", perPage:"每页", jump:"跳至", go:"前往", pagination:"传输记录分页", first:"第一页", previous:"上一页", next:"下一页", last:"最后一页", page:n=>`第 ${n} 页`,
  count:n=>`符合条件 ${n} 项`, updated:time=>`更新于 ${time}`, olderPage:"此页不自动刷新", pageSummary:(page,pages,start,end,total)=>`第 ${page} / ${pages} 页 · ${start}–${end} / ${total} 项`, loading:en?"Loading receiver records…":"正在读取接收端记录…", sessionExpired:en?"Session expired or revoked. Enter the current code from your Pixel.":"会话已失效或被撤销，请输入 Pixel 当前访问码重新登录。", noId:en?"This record has no identifier. Retry it on the Pixel.":"这条记录没有可用标识，请在 Pixel 上重试。", retryError:en?"The receiver could not submit the retry. Try again later; originals are retained.":"接收端未能提交重试。请稍后再试，原件仍保留。", requestSubmitted:en?"Retry submitted. Waiting for updated receiver results.":"重试已提交，等待接收端更新处理结果。", unknown:"—", oldTime:"未记录", noCapture:"未知", noSender:"未知发送设备", noItems:"没有符合条件的传输记录。",
  loginError:"访问码不对，请查看手机后重试。", locked:"尝试次数过多，请五分钟后重试。", connectionError:"无法连接 Pixel，请确认接收和浏览器管理仍已开启。", retried:n=>`已将 ${n} 项失败记录重新排队。`,
  detailTitle:"传输详情", close:"关闭详情", senders:"发送设备", progress:"接收进度", originals:"原件状态", error:"处理提示", originalsReceiving:"仍在接收", originalsRetained:"未从 Pixel 清理", originalsReleased:"接收端原件已清理", conversion:"需在 Pixel 开启兼容转换后重试", unsupported:"Pixel 无法处理这种媒体格式", burstMpf:"连拍 JPEG 含 MPF 多图片元数据", burstExtendedXmp:"连拍 JPEG 含扩展 XMP", burstMultipleXmp:"连拍 JPEG 含多个标准 XMP 数据包", burstXmpConflict:"连拍 JPEG 已有冲突的连拍标记", burstXmp:"连拍 JPEG 的 XMP 结构不受支持", burstStructure:"连拍 JPEG 的标记结构不受支持", retryHelp:"请在 Pixel 重试；若再次失败，可查看接收端诊断信息", cloud:"加入手机相册不代表 Google 相册云端已备份。"
};
const textIds = {
  "brand-subtitle":"brand","side-section":"section","nav-overview":"navOverview","nav-transfers":"navTransfers","sidebar-local":"local","breadcrumb-current":"breadcrumb","top-local":"topLocal","login-title":"loginTitle","login-help":"loginHelp","code-label":"code","login-button":"enter","eyebrow":"eyebrow","page-title":"title","page-description":"description","live-text":"live",
  "label-received":"received","received-hint":"receivedHint","label-published":"published","published-hint":"publishedHint","label-waiting":"waiting","waiting-hint":"waitingHint","label-failed":"failed","failed-hint":"failedHint","device-title":"deviceTitle","device-note":"deviceNote","temperature-label":"temperatureLabel","battery-label":"batteryLabel","free-label":"freeLabel","reserved-label":"reservedLabel","transfers-title":"transfers","table-note":"tableNote","retry":"retry",
  "guide-title":"guideTitle","guide-receiving":"receivingState","guide-waiting":"waitingState","guide-published":"publishedState","guide-failed":"failedState","guide-receiving-help":"guideReceiving","guide-waiting-help":"guideWaiting","guide-published-help":"guidePublished","guide-failed-help":"guideFailed",
  "state-label":"state","kind-label":"kind","auto-label":"auto","refresh-label":"refresh","col-file":"file","col-status":"status","col-captured":"captured","col-size":"amount","per-page-label":"perPage","jump-label":"jump","jump-button":"go",
  "details-eyebrow":"detailTitle","dt-status":"status","dt-kind":"kind","dt-burst":"burstRole","dt-senders":"senders","dt-captured":"captured","dt-received":"receivedTime","dt-published":"publishedTime","dt-progress":"progress","dt-originals":"originals","dt-error":"error","details-cloud-note":"cloud"
};
for (const [id,key] of Object.entries(textIds)) $(id).textContent = w[key];
$("pagination").setAttribute("aria-label",w.pagination);
$("details-close").setAttribute("aria-label",w.close);
for (const [id,options] of Object.entries({"state-filter":{all:"allStates",receiving:"receiving",processing:"processing",published:"publishedFilter",failed:"failedFilter"},"kind-filter":{all:"allKinds",photo:"photo",video:"video",motion:"motion",burst:"burst"}})) {
  for (const [value,key] of Object.entries(options)) $(id).querySelector(`option[value="${value}"]`).textContent = w[key];
}
const tokenKey = "backupduck-dashboard-token";
function clearToken() { token = ""; sessionStorage.removeItem(tokenKey); localStorage.removeItem(tokenKey); }
let token = localStorage.getItem(tokenKey) || sessionStorage.getItem(tokenKey) || "";
$("remember-label").textContent = w.remember; $("logout").textContent = w.logout;
let currentPage = 1;
let requestedPage = 1;
let totalPages = 1;
let historyVersion = 0;
let historyLoading = false;
let historyKey = "";
let paginationKey = "";
let overviewLoading = false;
let detailRetryPending = false;
let allRetryPending = false;
const savedPageSize = localStorage.getItem("backupduck-dashboard-page-size");
$("per-page").value = ["20","50","100"].includes(savedPageSize) ? savedPageSize : "20";
const dateFormat = new Intl.DateTimeFormat(en ? "en" : "zh-CN", {year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit"});
const timeFormat = new Intl.DateTimeFormat(en ? "en" : "zh-CN", {hour:"2-digit",minute:"2-digit",second:"2-digit"});
function size(bytes) {
  if (bytes == null || !Number.isFinite(Number(bytes))) return w.unknown;
  const value = Number(bytes);
  if (value < 1024) return `${value} B`;
  const units = ["KB","MB","GB","TB"];
  let number = value / 1024, index = 0;
  while (number >= 1024 && index < units.length - 1) { number /= 1024; index++; }
  return `${number.toFixed(number >= 10 ? 0 : 1)} ${units[index]}`;
}
function date(ms, missing = w.oldTime) {
  if (!Number.isFinite(ms) || ms <= 0) return missing;
  const value = new Date(ms);
  return Number.isNaN(value.getTime()) ? missing : dateFormat.format(value);
}
function feedback(id,value,isError = false) {
  const host = $(id); host.textContent = value; host.hidden = !value; host.classList.toggle("error",isError);
}
function message(value,isError = false) { feedback("dashboard-feedback",value,isError); }
function resetDashboard() {
  historyVersion++; historyKey = ""; paginationKey = ""; currentPage = 1; requestedPage = 1; totalPages = 1;
  $("items").replaceChildren(); $("recent-items").replaceChildren(); $("pagination").replaceChildren();
  for(const id of ["received","published","waiting","failed","temperature","battery","free","reserved","storage-free","storage-total","storage-originals","storage-minimum","settings-thermal","settings-threshold"]) $(id).textContent = w.unknown;
  feedback("message",""); message("");
}
function loginView(value = "") {
  $("details-dialog").close(); $("help-dialog").close(); $("retry-dialog").close();
  $("login-panel").hidden = false; $("dashboard").hidden = true;
  resetDashboard(); feedback("login-message",value,Boolean(value)); $("code").focus();
}
async function api(path, options = {}) {
  const headers = {...(options.headers || {})};
  if (token) headers.Authorization = `Bearer ${token}`;
  const requestToken = token;
  const response = await fetch(path, {...options, headers, cache:"no-store"});
  if (path !== "/api/login" && requestToken !== token) throw new Error("login");
  if (response.status === 401 && path !== "/api/login") {
    clearToken();
    loginView(w.sessionExpired);
    throw new Error("login");
  }
  if (!response.ok) throw new Error(String(response.status));
  if (response.status === 204) return null;
  return response.json();
}
function status(item) {
  if (item.receipt !== "received") return {key:"receiving",label:w.receivingState};
  if (item.processing === "complete") return {key:"published",label:w.publishedState};
  if (item.processing === "failed") return {key:"failed",label:w.failedState};
  return {key:"waiting",label:w.waitingState};
}
function processingNote(item) {
  if (item.processing !== "failed") return w.unknown;
  if (item.processing_error === "conversion_required") return w.conversion;
  if (item.processing_error === "unsupported") return w.unsupported;
  const burstReason = {
    burst_jpeg_mpf:"burstMpf", burst_jpeg_extended_xmp:"burstExtendedXmp",
    burst_jpeg_multiple_xmp:"burstMultipleXmp", burst_jpeg_xmp_conflict:"burstXmpConflict",
    burst_jpeg_xmp:"burstXmp", burst_jpeg_structure:"burstStructure"
  }[item.processing_error];
  if (burstReason) return w[burstReason];
  return w.retryHelp;
}
function kind(item) { return item.burst_primary == null || item.kind === "motion" ? item.kind : "burst"; }
function showDetails(item) {
  const retry = $("detail-retry");
  retry.hidden = item.processing !== "failed";
  retry.disabled = !item.id;
  feedback("detail-message",item.processing === "failed" && !item.id ? w.noId : "", !item.id);
  retry.onclick = async () => {
    if (!item.id || detailRetryPending) return;
    detailRetryPending = true;
    $("details-close").disabled = true;
    $("details-dialog").setAttribute("aria-busy", "true");
    retry.disabled = true; feedback("detail-message",en ? "Submitting retry…" : "正在提交重试…");
    try {
      const result = await api(`/api/retry?id=${encodeURIComponent(item.id)}`, {method:"POST"});
      feedback("detail-message",result.count ? w.requestSubmitted : (en ? "No failed record was queued." : "没有可重试的失败记录。"));
      // Keep feedback in this visible dialog; a queued request never becomes a success badge.
      await refreshAll();
    } catch (error) { if(error.message !== "login") feedback("detail-message",/^5[0-9]{2}$/.test(error.message) ? w.retryError : w.connectionError,true); }
    finally {
      detailRetryPending = false;
      retry.disabled = !item.id;
      $("details-close").disabled = false;
      $("details-dialog").setAttribute("aria-busy", "false");
    }
  };
  $("details-title").textContent = item.filename;
  $("detail-status").textContent = status(item).label;
  $("detail-kind").textContent = item.kind === "motion" && item.burst_primary != null ? `${w.motion} · ${w.burst}` : w[kind(item)] || w.unknown;
  $("dt-burst").hidden = item.burst_primary == null;
  $("detail-burst").hidden = item.burst_primary == null;
  $("detail-burst").textContent = item.burst_primary ? w.burstPrimary : w.burstOther;
  $("detail-senders").textContent = (item.senders || []).filter(Boolean).join(" · ") || w.noSender;
  $("detail-captured").textContent = date(item.captured_at_ms,w.noCapture);
  $("detail-received").textContent = date(item.received_at_ms,item.receipt === "received" ? w.oldTime : w.unknown);
  $("detail-published").textContent = date(item.published_at_ms,item.processing === "complete" ? w.oldTime : w.unknown);
  const total = Number(item.total_bytes) || 0, confirmed = Number(item.confirmed_bytes) || 0;
  $("detail-progress").textContent = `${size(confirmed)} / ${size(total)} (${total ? Math.min(100,Math.round(confirmed / total * 100)) : 0}%)`;
  $("detail-originals").textContent = item.receipt !== "received" ? w.originalsReceiving : item.originals_released ? w.originalsReleased : w.originalsRetained;
  $("detail-error").textContent = processingNote(item);
  $("details-dialog").showModal();
}
const icons = {
 photo:'<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 5-5 4 4 4-6 5 7"/>',
 video:'<rect x="3" y="5" width="13" height="14" rx="2"/><path d="m16 10 5-3v10l-5-3"/>',
 motion:'<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 1v2m0 18v2M1 12h2m18 0h2"/>',
 burst:'<rect x="3" y="7" width="14" height="14" rx="2"/><path d="M7 3h12a2 2 0 0 1 2 2v12"/>',
 transfer:'<path d="M7 21V3m-4 4 4-4 4 4M17 3v18m-4-4 4 4 4-4"/>',
 check:'<path d="m5 12 4 4L19 6"/>',
 clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
 alert:'<path d="m12 3 10 18H2Z"/><path d="M12 9v4m0 4v.1"/>',
 back:'<path d="m15 5-7 7 7 7"/>',
 chevron:'<path d="m9 5 7 7-7 7"/>',
 first:'<path d="m12 5-7 7 7 7m7-14-7 7 7 7"/>',
 last:'<path d="m5 5 7 7-7 7m7-14 7 7-7 7"/>'
};
function drawIcon(host,key) {
 const svg = document.createElementNS("http://www.w3.org/2000/svg","svg");
 svg.setAttribute("viewBox","0 0 24 24"); svg.setAttribute("fill","none"); svg.setAttribute("stroke","currentColor"); svg.setAttribute("stroke-width","1.7"); svg.setAttribute("aria-hidden","true"); svg.setAttribute("stroke-linecap","round"); svg.setAttribute("stroke-linejoin","round");
 // Only local constant paths enter this SVG. File names and API values use textContent.
 svg.innerHTML = icons[key] || icons.photo; host.replaceChildren(svg);
}
function decorateStatus(host,key) {
 const text = document.createElement("span"); text.textContent = host.textContent;
 const symbol = document.createElement("span"); symbol.className = "status-symbol"; drawIcon(symbol,{receiving:"transfer",waiting:"clock",published:"check",failed:"alert"}[key]);
 host.replaceChildren(symbol,text);
}
for(const key of ["receiving","waiting","published","failed"]) decorateStatus($("guide-"+key),key);
$("refresh").setAttribute("aria-label",en ? "Refresh records" : "立即刷新");
function cell(className, value) {
  const el = document.createElement("td"); el.className = className; el.textContent = value; return el;
}
function row(item) {
  const tr = document.createElement("tr"); tr.dataset.id = item.id || `${item.filename}/${item.received_at_ms}`; tr.dataset.value = JSON.stringify(item);
  const file = document.createElement("td"); file.className = "file-cell";
  const wrap = document.createElement("div"); wrap.className = "file-wrap";
  const itemKind = kind(item);
  const icon = document.createElement("span"); icon.className = `file-icon ${itemKind}`; drawIcon(icon,itemKind); icon.title = w[itemKind];
  const detail = document.createElement("div"); detail.className = "file-detail";
  const name = document.createElement("button"); name.type = "button"; name.className = "file-name"; name.textContent = item.filename; name.title = item.filename; name.addEventListener("click",() => showDetails(item));
  const subtitle = document.createElement("small"); subtitle.textContent = w[itemKind] || w.unknown; detail.append(name,subtitle); wrap.append(icon,detail); file.append(wrap);
  const state = status(item);
  const statusCell = document.createElement("td");
  const badge = document.createElement("span"); badge.className = `status-badge ${state.key}`; badge.textContent = state.label; decorateStatus(badge,state.key);
  statusCell.append(badge);
  const ratio = item.total_bytes > 0 ? Number(item.confirmed_bytes) / Number(item.total_bytes) : 0;
  if(item.receipt !== "received" && ratio > 0 && ratio < 1) {
    statusCell.className = "status-cell";
    const progress = document.createElement("div"); progress.className = "transfer-progress";
    progress.setAttribute("role","progressbar"); progress.setAttribute("aria-label",w.progress);
    progress.setAttribute("aria-valuenow",String(Math.round(ratio*100))); progress.setAttribute("aria-valuemin","0"); progress.setAttribute("aria-valuemax","100");
    const fill = document.createElement("span"); fill.style.width = `${ratio*100}%`; progress.append(fill); statusCell.append(progress);
  }
  const amount = item.receipt === "received" ? size(item.total_bytes) : `${size(item.confirmed_bytes)} / ${size(item.total_bytes)}`;
  tr.append(file,statusCell,cell("date-cell",date(item.captured_at_ms,w.noCapture)),cell("size-cell",amount));
  return tr;
}
function pageButton(label,target,disabled,active,ariaLabel) {
  const button = document.createElement("button"); button.type = "button"; button.textContent = label; if(icons[label]) drawIcon(button,label); button.disabled = disabled; button.setAttribute("aria-label",ariaLabel);
  if (active) { button.className = "active"; button.setAttribute("aria-current","page"); }
  button.addEventListener("click",() => loadHistory(target));
  return button;
}
function renderPagination() {
  const key = `${currentPage}/${totalPages}`;
  if (key !== paginationKey) {
    const controls = [pageButton("first",1,currentPage === 1,false,w.first),pageButton("back",currentPage-1,currentPage === 1,false,w.previous)];
    const visible = new Set([1,totalPages]);
    for (let page = Math.max(1,currentPage-2); page <= Math.min(totalPages,currentPage+2); page++) visible.add(page);
    let previous = 0;
    for (const page of [...visible].sort((a,b) => a-b)) {
      if (page-previous > 1) { const dots = document.createElement("span"); dots.className = "page-ellipsis"; dots.textContent = "…"; controls.push(dots); }
      controls.push(pageButton(String(page),page,page === currentPage,page === currentPage,w.page(page)));
      previous = page;
    }
    controls.push(pageButton("chevron",currentPage+1,currentPage === totalPages,false,w.next),pageButton("last",totalPages,currentPage === totalPages,false,w.last));
    $("pagination").replaceChildren(...controls); paginationKey = key;
  }
  $("jump-page").max = String(totalPages);
  if (document.activeElement !== $("jump-page")) $("jump-page").value = String(currentPage);
}
async function loadHistory(targetPage = requestedPage) {
  requestedPage = targetPage;
  const version = ++historyVersion;
  historyLoading = true; $("history-table").setAttribute("aria-busy","true");
  if(!historyKey) { const tr=document.createElement("tr"), td=cell("empty-row",w.loading); td.colSpan=4; tr.append(td); $("items").replaceChildren(tr); }
  const perPage = Number($("per-page").value);
  const params = new URLSearchParams({search:$("search-files").value.trim(),state:$("state-filter").value,kind:$("kind-filter").value,page:String(targetPage),per_page:String(perPage)});
  try {
    const result = await api(`/api/history?${params}`);
    if (version !== historyVersion) return;
    const pages = Math.max(1,Number(result.pages) || 1);
    if (targetPage > pages) { await loadHistory(pages); return; }
    const key = JSON.stringify([params.toString(),result.items]);
    if (key !== historyKey) {
      const tbody = $("items"); const old = new Map([...tbody.children].map(tr=>[tr.dataset.id,tr]));
      const focusedId = document.activeElement?.closest("tr")?.dataset.id;
      const rows = result.items.map(item=> {
        const id = item.id || `${item.filename}/${item.received_at_ms}`; const existing = old.get(id);
        return existing?.dataset.value === JSON.stringify(item) ? existing : row(item);
      });
      tbody.replaceChildren(...rows);
      if(focusedId) rows.find(tr=>tr.dataset.id === focusedId)?.querySelector(".file-name")?.focus({preventScroll:true});
      if(!rows.length) { const tr=document.createElement("tr"), td=cell("empty-row",w.noItems); td.colSpan=4; tr.append(td); tbody.append(tr); }
    }
    historyKey = key;
    currentPage = targetPage; totalPages = pages;
    $("result-count").textContent = w.count(result.total);
    $("updated-at").textContent = `${w.updated(timeFormat.format(new Date()))}${currentPage > 1 ? ` · ${w.olderPage}` : ""}`;
    const start = result.total ? (currentPage-1)*perPage+1 : 0;
    const end = Math.min(currentPage*perPage,result.total);
    $("page-summary").textContent = w.pageSummary(currentPage,totalPages,start,end,result.total);
    renderPagination();
    feedback("message",result.total === 0 ? w.noItems : "");
  } catch (error) { if (error.message !== "login" && version === historyVersion) feedback("message",w.connectionError,true); }
  finally { if (version === historyVersion) { historyLoading = false; $("history-table").setAttribute("aria-busy","false"); } }
}
async function overview() {
  if (!token || overviewLoading) return;
  overviewLoading = true;
  try {
    const value = await api("/api/overview");
    $("received").textContent = value.received == null || value.total == null ? w.unknown : `${value.received} / ${value.total}`;
    $("published").textContent = value.published == null ? w.unknown : String(value.published);
    $("waiting").textContent = value.waiting == null ? w.unknown : String(value.waiting);
    $("failed").textContent = value.failed == null ? w.unknown : String(value.failed);
    $("reserved").textContent = size(value.reserved_bytes);
    $("reserved-detail").textContent = w.originalsDetail;
    $("free").textContent = size(value.free_bytes);
    $("free-detail").textContent = w.spaceDetail(value.total_space_bytes,value.min_free_bytes);
    $("storage-free").textContent = size(value.free_bytes);
    $("storage-total").textContent = size(value.total_space_bytes);
    $("storage-originals").textContent = size(value.reserved_bytes);
    $("storage-minimum").textContent = size(value.min_free_bytes);
    const meter = $("storage-meter");
    meter.value = value.total_space_bytes > 0 ? Math.max(0,Math.min(1,1-value.free_bytes/value.total_space_bytes)) : 0;
    meter.hidden = !(value.total_space_bytes > 0);
    const device = value.device;
    $("settings-thermal").textContent = device?.thermal_enabled == null ? w.waitingReading : device.thermal_enabled ? (en ? "Enabled" : "已开启") : w.thermalOff;
    $("settings-threshold").textContent = device?.thermal_threshold_celsius == null ? w.unknown : `${device.thermal_threshold_celsius} °C`;
    $("temperature").textContent = device?.temperature_deci_celsius == null ? w.unknown : `${(device.temperature_deci_celsius / 10).toFixed(1)} °C`;
    $("thermal-state").textContent = device?.thermal_enabled == null ? w.waitingReading : device.thermal_held ? w.thermalPaused : device.thermal_enabled ? w.threshold(device.thermal_threshold_celsius) : w.thermalOff;
    $("thermal-state").classList.toggle("held",Boolean(device?.thermal_held));
    $("battery").textContent = device?.battery_percent == null ? w.unknown : `${device.battery_percent}%`;
    $("battery-state").textContent = device?.charging == null ? w.waitingReading : device.charging ? w.charging : w.notCharging;
    $("device-note").textContent = w.updated(timeFormat.format(new Date()));
    $("live-text").textContent = w.live;
    $("live-text").parentElement.classList.remove("offline");
    message("");
  } catch (error) {
    if (error.message !== "login") { message(w.connectionError,true); $("live-text").textContent = w.connectionError; $("live-text").parentElement.classList.add("offline"); }
  } finally { overviewLoading = false; }
}
async function refreshAll() { if(token) await Promise.all([overview(),loadHistory(),loadRecent()]); }
async function loadRecent() {
  if (!token) return;
  try {
    const result = await api("/api/history?page=1&per_page=20&state=all&kind=all");
    $("recent-items").replaceChildren(...result.items.slice(0,4).map(row));
    if (!result.items.length) { const tr = document.createElement("tr"); const td = cell("",w.noItems); td.colSpan = 4; tr.append(td); $("recent-items").append(tr); }
  } catch(error) { if(error.message !== "login") message(w.connectionError); }
}
async function show() { $("login-panel").hidden = true; $("dashboard").hidden = false; selectPage(); await refreshAll(); }
$("login-form").addEventListener("submit",async event => {
  event.preventDefault();
  const code = $("code").value.trim(); if (!/^[0-9]{10}$/.test(code)) return;
  $("login-button").disabled = true; feedback("login-message",en ? "Connecting…" : "正在连接…");
  try {
    const result = await api("/api/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({code,remember:$("remember").checked})});
    clearToken(); token = result.token; ($("remember").checked ? localStorage : sessionStorage).setItem(tokenKey,token);
    $("code").value = ""; feedback("login-message",""); resetDashboard(); await show();
  } catch (error) { feedback("login-message",error.message === "429" ? w.locked : error.message === "401" ? w.loginError : w.connectionError,true); }
  finally { $("login-button").disabled = false; }
});
$("logout").addEventListener("click", async () => {
  $("logout").disabled = true;
  try { await api("/api/logout", {method:"POST"}); clearToken(); loginView(); }
  catch(error) { if(error.message !== "login") message(w.connectionError,true); }
  finally { $("logout").disabled = false; }
});
$("state-filter").addEventListener("change",() => loadHistory(1));
$("kind-filter").addEventListener("change",() => loadHistory(1));
$("per-page").addEventListener("change",() => { localStorage.setItem("backupduck-dashboard-page-size",$("per-page").value); loadHistory(1); });
$("refresh").addEventListener("click",async()=> { $("refresh").disabled = true; await refreshAll(); $("refresh").disabled = false; });
$("jump-form").addEventListener("submit",event => {
  event.preventDefault();
  const page = Number($("jump-page").value);
  if (Number.isInteger(page) && page >= 1 && page <= totalPages) loadHistory(page);
});
$("details-close").addEventListener("click",() => { if (!detailRetryPending) $("details-dialog").close(); });
$("details-dialog").addEventListener("cancel", event => { if (detailRetryPending) event.preventDefault(); });
$("retry-dialog").addEventListener("cancel", event => { if (allRetryPending) event.preventDefault(); });
$("retry").addEventListener("click",()=> {feedback("retry-message",""); $("retry-dialog").showModal();});
$("retry-cancel").addEventListener("click",()=> { if (!allRetryPending) $("retry-dialog").close(); });
$("retry-confirm").addEventListener("click",async () => {
  if (allRetryPending) return;
  allRetryPending = true;
  $("retry-dialog").setAttribute("aria-busy", "true");
  $("retry-confirm").disabled = true; $("retry-cancel").disabled = true;
  feedback("retry-message",en?"Submitting retry…":"正在提交重试…");
  try { const result = await api("/api/retry",{method:"POST"});
    feedback("retry-message",result.count ? w.retried(result.count) : (en ? "No failed record was queued." : "没有可重试的失败记录。")); await refreshAll();
  } catch (error) { if(error.message !== "login") feedback("retry-message",/^5[0-9]{2}$/.test(error.message) ? w.retryError : w.connectionError,true); }
  finally {
    allRetryPending = false;
    $("retry-dialog").setAttribute("aria-busy", "false");
    $("retry-confirm").disabled = false; $("retry-cancel").disabled = false;
  }
});
$("auto-refresh").checked = localStorage.getItem("backupduck-dashboard-auto-refresh") !== "off";
$("auto-refresh").addEventListener("change",() => localStorage.setItem("backupduck-dashboard-auto-refresh",$("auto-refresh").checked ? "on" : "off"));

setInterval(() => {
  if (!token || !$("auto-refresh").checked || document.visibilityState !== "visible") return;
  overview();
  if(location.hash === "#overview" || !location.hash) loadRecent();
  if (currentPage === 1 && !historyLoading) loadHistory();
},8000);

// Navigation keeps filter, page and scroll state rather than rebuilding tables.
const pageNames = {overview:en?"Overview":"总览",transfers:en?"Transfers":"传输记录",storage:en?"Storage":"存储",settings:en?"Settings":"设置"};
let activePanel = null; const panelScroll = new Map();
function selectPage(value = location.hash.slice(1)) {
  const page = pageNames[value] ? value : "overview";
  const changed = activePanel !== page;
  if(changed && activePanel && !$("dashboard").hidden) panelScroll.set(activePanel,window.scrollY);
  activePanel = page;
  document.querySelectorAll("[data-page-panel]").forEach(panel => panel.hidden = panel.dataset.pagePanel !== page);
  document.querySelectorAll(".side-link[data-page]").forEach(link => {
    const active = link.dataset.page === page; link.classList.toggle("active",active);
    if (active) link.setAttribute("aria-current","page"); else link.removeAttribute("aria-current");
  });
  $("page-title").textContent = pageNames[page];
  $("breadcrumb-current").textContent = pageNames[page];
  $("page-description").hidden = page !== "overview";
  if(changed) requestAnimationFrame(()=>window.scrollTo({top:panelScroll.get(page) || 0,behavior:"instant"}));
}
document.querySelectorAll("[data-page]").forEach(link => link.addEventListener("click",event => {
  event.preventDefault(); location.hash = link.dataset.page; selectPage(link.dataset.page);
}));
window.addEventListener("hashchange",() => selectPage());
document.querySelectorAll("[data-zh]").forEach(el => el.textContent = en ? el.dataset.en : el.dataset.zh);
$("search-files").placeholder = en ? "Find a filename" : "查找文件名";
$("search-files").setAttribute("aria-label",$("search-files").placeholder);
let searchTimer;
$("search-files").addEventListener("input",() => { clearTimeout(searchTimer); searchTimer = setTimeout(() => loadHistory(1),250); });
function setAppearance(mode) {
  const valid = ["system","light","dark"].includes(mode) ? mode : "system";
  if(valid === "system") delete document.documentElement.dataset.theme; else document.documentElement.dataset.theme = valid;
  $("appearance").value = valid; localStorage.setItem("backupduck-dashboard-appearance",valid);
}
setAppearance(localStorage.getItem("backupduck-dashboard-appearance") || "system");
$("appearance").addEventListener("change",event => setAppearance(event.target.value));
$("theme-toggle").addEventListener("click",() => {
  const dark = document.documentElement.dataset.theme === "dark" || (!document.documentElement.dataset.theme && matchMedia("(prefers-color-scheme:dark)").matches);
  setAppearance(dark ? "light" : "dark");
});
$("settings-auto").checked = $("auto-refresh").checked;
$("settings-auto").addEventListener("change",event => { $("auto-refresh").checked = event.target.checked; $("auto-refresh").dispatchEvent(new Event("change")); });
$("auto-refresh").addEventListener("change",event => $("settings-auto").checked = event.target.checked);
$("help-open").addEventListener("click",()=>$("help-dialog").showModal());
$("help-close").addEventListener("click",()=>$("help-dialog").close());
$("help-close").setAttribute("aria-label",en?"Close help":"关闭帮助");
document.documentElement.lang = en ? "en" : "zh-CN";
selectPage();
if (token) show();
