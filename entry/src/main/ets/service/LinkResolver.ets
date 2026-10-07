// LinkResolver：B 站链接识别与短链解析集中地（PROJECT_NOTES.md KI-4 闭环）。
// 职责：
//   ① 分享文案前置抽取（extractBiliUrl）：从混排文本中抽出第一个 B 站域名 http(s) 链接并清除尾随标点；
//   ② 短链判定与裸域名归一化（isBiliShortLink / normalizeShortLinkUrl）；
//   ③ 短链解析（resolveShortLink）：maxRedirects:0 禁跟随重定向 + 直读 3xx Location（大小写不敏感、
//      相对地址补全），迭代跟进 ≤3 跳，最终目标须为 bilibili.com 域名；会话级 LRU 缓存仅存成功结果；
//      短链路径含视频号时零网络短路；正文兜底只提取 bilibili.com 完整 URL（禁止裸扫孤立 BV 号，防误播）；
//   ④ 目标识别（recognizeInput）：BV / av / 收藏夹 / 合集 / 系列 / UP 空间（含移动端形态），先命中先返回。
// 纯函数 + 模块级缓存，无 UI 依赖；页面（AddSubscriptionSheet）仅做编排与分发。

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';
import { Constants } from './Constants';
import { USER_AGENT, REFERER } from './BiliService';

// —— 数据模型 ——

// 识别结果：type 取 '' | 'bv' | 'av' | 'up' | 'fav' | 'season' | 'series'
export class RecognizeResult {
  type: string = '';
  id: string = '';
  ownerMid: string = '';
}

// 短链解析结局：成功 | 网络失败 | 超出跳数 | 无有效目标 | 目标无法识别
export enum ShortLinkOutcome {
  OK = 'ok',
  NETWORK = 'network',
  HOPS = 'hops',
  NO_TARGET = 'no-target',
  UNRECOGNIZED = 'unrecognized',
}

// 短链解析结果：失败时 target 为空、message 为面向用户的中文分型提示（plan.md D4：结果模型而非异常）
export class ShortLinkResult {
  outcome: ShortLinkOutcome = ShortLinkOutcome.OK;
  target: string = '';
  message: string = '';
}

// —— 链接前置抽取（FR-001 / D9） ——

// 尾随标点清除集：中英文句号/叹号/问号/分号/冒号/右括号/右书名号/引号等（分享文案常见）
const TRAILING_PUNCTUATION: string = '.,!?;:)]>\'"”，。！？；：）】」』》”’…';

function stripTrailingPunctuation(url: string): string {
  let end: number = url.length;
  while (end > 0 && TRAILING_PUNCTUATION.indexOf(url.charAt(end - 1)) >= 0) {
    end--;
  }
  return url.substring(0, end);
}

// 抽取文本中第一个 B 站域名（b23.tv / bili2233.cn / bilibili.com 及任意子域，忽略大小写，须带 http(s) 前缀）
// 的链接并清除尾随标点；未抽到时返回原始去空格文本，供后续分支统一使用清洗结果。
export function extractBiliUrl(raw: string): string {
  const m: RegExpExecArray | null = new RegExp(
    'https?:\\/\\/(?:[0-9A-Za-z-]+\\.)*(?:b23\\.tv|bili2233\\.cn|bilibili\\.com)(?![0-9A-Za-z.-])(?:[/?#][^\\s]*)?',
    'i').exec(raw);
  if (m === null) {
    return raw.trim();
  }
  return stripTrailingPunctuation(m[0]);
}

// —— 目标识别（自 AddSubscriptionSheet.ets 迁入；先命中先返回，语义与迁移前一致） ——

export function recognizeInput(input: string): RecognizeResult {
  const r: RecognizeResult = new RecognizeResult();
  const trimmed: string = input.trim();
  if (trimmed === '') {
    return r;
  }
  let m: RegExpExecArray | null = new RegExp('BV[0-9A-Za-z]{10}').exec(trimmed);
  if (m !== null) {
    r.type = 'bv';
    r.id = m[0];
    return r;
  }
  // av 号（忽略大小写，如 av170001 / AV170001），置于 BV 分支之后
  m = new RegExp('^av(\\d+)$', 'i').exec(trimmed);
  if (m !== null) {
    r.type = 'av';
    r.id = m[1];
    return r;
  }
  // av 号 URL 形态（KI-4 修复 / US4）：bilibili.com/video/av{数字}（忽略大小写，含 m. 等任意子域路径）
  m = new RegExp('bilibili\\.com/video/av(\\d+)', 'i').exec(trimmed);
  if (m !== null) {
    r.type = 'av';
    r.id = m[1];
    return r;
  }
  // lists 规则（KI-4 修复 / US4）：host 放宽为 bilibili.com 任意子域，路径兼容桌面 {host}/{mid}/lists/{id}
  // 与移动端 {host}/space/{mid}/lists/{id} 两种形态；桌面形态行为不变
  m = new RegExp('(?:[0-9A-Za-z-]+\\.)*bilibili\\.com(?:/space)?/(\\d+)/lists/(\\d+)').exec(trimmed);
  if (m !== null) {
    r.ownerMid = m[1];
    r.id = m[2];
    r.type = new RegExp('type=series').test(trimmed) ? 'series' : 'season';
    return r;
  }
  m = new RegExp('seriesdetail\\?[^&]*sid=(\\d+)').exec(trimmed);
  if (m !== null) {
    r.type = 'series';
    r.id = m[1];
    // ownerMid 提取同步放宽为任意子域 + 可选 /space 路径前缀（桌面形态行为不变）
    const midM: RegExpExecArray | null = new RegExp('(?:[0-9A-Za-z-]+\\.)*bilibili\\.com(?:/space)?/(\\d+)').exec(trimmed);
    if (midM !== null) {
      r.ownerMid = midM[1];
    }
    return r;
  }
  m = new RegExp('collectiondetail\\?[^&]*sid=(\\d+)').exec(trimmed);
  if (m !== null) {
    r.type = 'season';
    r.id = m[1];
    // ownerMid 提取同步放宽为任意子域 + 可选 /space 路径前缀（桌面形态行为不变）
    const midM: RegExpExecArray | null = new RegExp('(?:[0-9A-Za-z-]+\\.)*bilibili\\.com(?:/space)?/(\\d+)').exec(trimmed);
    if (midM !== null) {
      r.ownerMid = midM[1];
    }
    return r;
  }
  m = new RegExp('(?:fid|media_id)=(\\d+)').exec(trimmed);
  if (m !== null && (trimmed.indexOf('fav') >= 0 || trimmed.indexOf('collection') >= 0 || trimmed.indexOf('favlist') >= 0)) {
    r.type = 'fav';
    r.id = m[1];
    return r;
  }
  // UP 空间移动端形态（KI-4 修复 / US2）：host 为 bilibili.com 任意子域（含 m.）的 /space/{数字} 路径
  // （实测空间短链 302 的 Location 形如 https://m.bilibili.com/space/475656353?plat_id=...）
  m = new RegExp('bilibili\\.com/space/(\\d+)').exec(trimmed);
  if (m !== null) {
    r.type = 'up';
    r.id = m[1];
    return r;
  }
  m = new RegExp('space\\.bilibili\\.com/(\\d+)').exec(trimmed);
  if (m !== null) {
    r.type = 'up';
    r.id = m[1];
    return r;
  }
  m = new RegExp('^(\\d+)$').exec(trimmed);
  if (m !== null) {
    r.type = 'up';
    r.id = m[1];
    return r;
  }
  return r;
}

// —— 短链判定与归一化（FR-002） ——

// 提取 URL 的 host（小写化）；无 http(s) 前缀时返回空串
function urlHost(url: string): string {
  const m: RegExpExecArray | null = new RegExp('^https?:\\/\\/([^\\/?#]+)', 'i').exec(url);
  return m !== null ? m[1].toLowerCase() : '';
}

// 短链判定：host 为 b23.tv / bili2233.cn（忽略大小写）
export function isBiliShortLink(url: string): boolean {
  const host: string = urlHost(url);
  return host === 'b23.tv' || host === 'bili2233.cn';
}

// B 站主站域名判定（短链解析最终目标校验，FR-003）：bilibili.com 及任意子域
function isBiliSiteUrl(url: string): boolean {
  const host: string = urlHost(url);
  return host === 'bilibili.com' || host.endsWith('.bilibili.com');
}

// 裸域名归一化：无协议前缀的裸短链（如 b23.tv/xxx）补 https:// 后再处理
export function normalizeShortLinkUrl(url: string): string {
  const trimmed: string = url.trim();
  if (trimmed === '') {
    return trimmed;
  }
  if (new RegExp('^https?:\\/\\/', 'i').test(trimmed)) {
    return trimmed;
  }
  return `https://${trimmed}`;
}

// —— 短链解析（FR-003 ~ FR-007 / plan.md D1/D3/D4/D6/D7/D8） ——

const MAX_REDIRECT_HOPS: number = 3;
const SHORT_LINK_CACHE_MAX: number = 50;
// 会话级缓存：键为 host 小写化的规范化短链；Map 与顺序数组同步维护插入序，命中先删后插实现 LRU；
// 不持久化、不设 TTL，仅缓存 outcome='ok' 的结果
const shortLinkCache: Map<string, ShortLinkResult> = new Map<string, ShortLinkResult>();
const shortLinkCacheOrder: string[] = [];

// 日志摘要：仅保留 host+path，截掉可能含 token 的 query string（与 BiliService.logUrl 同语义）
function logSummary(url: string): string {
  const qIdx: number = url.indexOf('?');
  return qIdx >= 0 ? url.substring(0, qIdx) : url;
}

function makeOk(target: string): ShortLinkResult {
  const r: ShortLinkResult = new ShortLinkResult();
  r.outcome = ShortLinkOutcome.OK;
  r.target = target;
  r.message = '';
  return r;
}

function makeError(outcome: ShortLinkOutcome, message: string): ShortLinkResult {
  const r: ShortLinkResult = new ShortLinkResult();
  r.outcome = outcome;
  r.target = '';
  r.message = message;
  return r;
}

// 短链 path 内视频号短路（D7）：如 b23.tv/BV1iMtG6YEyr，path 命中 BV+10 位字母数字时
// 直接产出视频页目标，零网络请求、不写缓存
function shortLinkBvTarget(url: string): string {
  const m: RegExpExecArray | null = new RegExp('^https?:\\/\\/[^\\/?#]+([^?#]*)', 'i').exec(url);
  if (m === null) {
    return '';
  }
  const bv: RegExpExecArray | null = new RegExp('BV[0-9A-Za-z]{10}').exec(m[1]);
  return bv !== null ? `https://www.bilibili.com/video/${bv[0]}` : '';
}

// 缓存键：host 小写化的规范化短链
function shortLinkCacheKey(url: string): string {
  const m: RegExpExecArray | null = new RegExp('^(https?:\\/\\/)([^\\/?#]+)([\\s\\S]*)$', 'i').exec(url);
  if (m === null) {
    return url;
  }
  return `${m[1]}${m[2].toLowerCase()}${m[3]}`;
}

// 命中先删后插（LRU 新鲜度，Map 与顺序数组同步）；未命中返回 null
function cacheGet(key: string): ShortLinkResult | null {
  const cached: ShortLinkResult | undefined = shortLinkCache.get(key);
  if (cached === undefined) {
    return null;
  }
  shortLinkCache.delete(key);
  shortLinkCache.set(key, cached);
  const idx: number = shortLinkCacheOrder.indexOf(key);
  if (idx >= 0) {
    shortLinkCacheOrder.splice(idx, 1);
  }
  shortLinkCacheOrder.push(key);
  return cached;
}

// 仅缓存成功结果；超容量淘汰最旧键（顺序数组首元素）
function cachePut(key: string, result: ShortLinkResult): void {
  if (result.outcome !== ShortLinkOutcome.OK) {
    return;
  }
  if (shortLinkCache.has(key)) {
    shortLinkCache.delete(key);
    const idx: number = shortLinkCacheOrder.indexOf(key);
    if (idx >= 0) {
      shortLinkCacheOrder.splice(idx, 1);
    }
  }
  shortLinkCache.set(key, result);
  shortLinkCacheOrder.push(key);
  while (shortLinkCacheOrder.length > SHORT_LINK_CACHE_MAX) {
    const oldest: string = shortLinkCacheOrder.shift() ?? '';
    if (oldest !== '') {
      shortLinkCache.delete(oldest);
    }
  }
}

// response.header 为 Object 且键大小写不定：收窄为 Record 后按候选大小写查找 location
function readLocationHeader(header: Object): string {
  const headers: Record<string, Object> = header as Record<string, Object>;
  const candidates: string[] = ['location', 'Location', 'LOCATION'];
  for (let i: number = 0; i < candidates.length; i++) {
    const value: Object = headers[candidates[i]];
    if (typeof value === 'string' && value !== '') {
      return value;
    }
  }
  return '';
}

// 相对 Location 补全（D1）：按当前请求的协议+域名转为绝对地址
function resolveLocationTarget(location: string, currentUrl: string): string {
  const loc: string = location.trim();
  if (new RegExp('^https?:\\/\\/', 'i').test(loc)) {
    return loc;
  }
  const originMatch: RegExpExecArray | null = new RegExp('^(https?:\\/\\/[^\\/?#]+)', 'i').exec(currentUrl);
  const origin: string = originMatch !== null ? originMatch[1] : 'https://b23.tv';
  if (loc.startsWith('//')) {
    // 协议相对地址 //host/path
    const scheme: string = origin.substring(0, origin.indexOf('://'));
    return `${scheme}:${loc}`;
  }
  if (loc.startsWith('/')) {
    return `${origin}${loc}`;
  }
  return `${origin}/${loc}`;
}

// 正文兜底（D6 / FR-009）：仅当响应非 3xx（无 Location 可读）时启用；
// 只提取正文中带 bilibili.com 域名（任意子域）的完整 URL 且须能被识别器分类，禁止裸扫孤立 BV 号
function extractBiliSiteUrlFromBody(body: string): string {
  const pattern: RegExp = new RegExp('https?:\\/\\/(?:[0-9A-Za-z-]+\\.)*bilibili\\.com\\/[^\\s"\'<>]+', 'gi');
  let m: RegExpExecArray | null = pattern.exec(body);
  while (m !== null) {
    if (recognizeInput(m[0]).type !== '') {
      return m[0];
    }
    m = pattern.exec(body);
  }
  return '';
}

// 单跳请求：maxRedirects:0 禁跟随重定向 + 直读 Location；专用超时；与主站一致的 UA/Referer 头
async function requestShortLink(url: string): Promise<http.HttpResponse> {
  const httpRequest: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': USER_AGENT,
        'Referer': REFERER,
      },
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: Constants.SHORT_LINK_CONNECT_MS,
      readTimeout: Constants.SHORT_LINK_READ_MS,
      maxRedirects: 0,
    });
    return response;
  } finally {
    httpRequest.destroy();
  }
}

// 短链解析主链路：短路 → 缓存 → 迭代 302（≤3 跳）→ 正文兜底；失败按四类分型返回，不抛异常
export async function resolveShortLink(shortUrl: string): Promise<ShortLinkResult> {
  const normalized: string = normalizeShortLinkUrl(shortUrl);
  if (!isBiliShortLink(normalized)) {
    return makeError(ShortLinkOutcome.NO_TARGET, '不是有效的 B 站短链');
  }
  // 视频号短路：零网络、不写缓存
  const bvTarget: string = shortLinkBvTarget(normalized);
  if (bvTarget !== '') {
    Logger.log('net', logSummary(normalized), '短链路径含视频号，零网络短路');
    return makeOk(bvTarget);
  }
  // 缓存命中：零网络请求（日志点位于任何网络请求之前）
  const key: string = shortLinkCacheKey(normalized);
  const cached: ShortLinkResult | null = cacheGet(key);
  if (cached !== null) {
    Logger.log('net', logSummary(normalized), '短链缓存命中');
    return cached;
  }
  let current: string = normalized;
  try {
    for (let hop: number = 0; hop <= MAX_REDIRECT_HOPS; hop++) {
      const response: http.HttpResponse = await requestShortLink(current);
      Logger.log('net', logSummary(current), `HTTP ${response.responseCode}`);
      const code: number = response.responseCode;
      const location: string = readLocationHeader(response.header);
      if (code >= 300 && code < 400 && location !== '') {
        const target: string = resolveLocationTarget(location, current);
        if (isBiliShortLink(target)) {
          // Location 仍为短链域名：迭代跟进（上限 3 跳）
          if (hop === MAX_REDIRECT_HOPS) {
            return makeError(ShortLinkOutcome.HOPS, '短链跳转次数超出限制');
          }
          current = target;
          continue;
        }
        if (isBiliSiteUrl(target)) {
          const recognized: RecognizeResult = recognizeInput(target);
          if (recognized.type === '') {
            return makeError(ShortLinkOutcome.UNRECOGNIZED, '短链目标无法识别，暂不支持该类型页面');
          }
          const okResult: ShortLinkResult = makeOk(target);
          cachePut(key, okResult);
          return okResult;
        }
        return makeError(ShortLinkOutcome.NO_TARGET, '短链未指向有效的 B 站页面');
      }
      // 非 3xx 或无 Location：正文兜底（只提取可识别的 bilibili.com URL）
      const body: string = response.result as string;
      const extracted: string = extractBiliSiteUrlFromBody(body);
      if (extracted === '') {
        return makeError(ShortLinkOutcome.NO_TARGET, '短链未指向有效的 B 站页面');
      }
      const okResult: ShortLinkResult = makeOk(extracted);
      cachePut(key, okResult);
      return okResult;
    }
    return makeError(ShortLinkOutcome.HOPS, '短链跳转次数超出限制');
  } catch (error) {
    const err = error as BusinessError;
    Logger.log('error', logSummary(normalized), `短链解析网络失败: ${err.message}`);
    return makeError(ShortLinkOutcome.NETWORK, '短链解析网络失败，请检查网络后重试');
  }
}
