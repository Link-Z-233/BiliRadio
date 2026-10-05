import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BiliVideo } from '../model/BiliVideo';
import { FavFolder } from '../model/FavFolder';
import { Season } from '../model/Season';
import { BiliSession } from './BiliSession';
import { Constants, sleep } from './Constants';
import { WbiSigner } from './WbiSigner';
import { Logger } from './Logger';

const BILI_VIDEO_INFO_URL: string = 'https://api.bilibili.com/x/web-interface/view';
const BILI_PLAY_URL_API: string = 'https://api.bilibili.com/x/player/playurl';
const BILI_NAV_URL: string = 'https://api.bilibili.com/x/web-interface/nav';
const BILI_SPI_URL: string = 'https://api.bilibili.com/x/frontend/finger/spi';
const BILI_FAV_FOLDERS_URL: string = 'https://api.bilibili.com/x/v3/fav/folder/created/list-all';
const BILI_FAV_RESOURCE_URL: string = 'https://api.bilibili.com/x/v3/fav/resource/list';
const BILI_FAV_DEAL_URL: string = 'https://api.bilibili.com/x/v3/fav/resource/deal';
const BILI_SEASONS_SERIES_LIST_URL: string = 'https://api.bilibili.com/x/polymer/web-space/seasons_series_list';
const BILI_SEASONS_ARCHIVES_LIST_URL: string = 'https://api.bilibili.com/x/polymer/web-space/seasons_archives_list';
const BILI_SERIES_ARCHIVES_URL: string = 'https://api.bilibili.com/x/series/archives';
const BILI_SPACE_ARC_SEARCH_URL: string = 'https://api.bilibili.com/x/space/wbi/arc/search';
const BILI_SPACE_ARC_URL: string = 'https://api.bilibili.com/x/space/arc/search';
const BILI_SPACE_ACC_INFO_URL: string = 'https://api.bilibili.com/x/space/wbi/acc/info';
const BILI_CARD_URL: string = 'https://api.bilibili.com/x/web-interface/card';
const BILI_SERIES_META_URL: string = 'https://api.bilibili.com/x/series/series';
const BILI_QR_GENERATE_URL: string = 'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';
const BILI_QR_POLL_URL: string = 'https://passport.bilibili.com/x/passport-login/web/qrcode/poll';
export const REFERER: string = 'https://www.bilibili.com';
export const USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
// 空间接口风控三件套：PC Safari UA + space Referer/Origin（接口参数为公开事实性配置）
const SPACE_ORIGIN: string = 'https://space.bilibili.com';
const SPACE_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15';


export type PageProgressCallback = (fetchedCount: number, totalCount: number) => void;

export class QrLoginInfo {
  url: string = '';
  qrcodeKey: string = '';
}

export enum QrPollStatus {
  WAITING = 0,
  SCANNED = 1,
  EXPIRED = 2,
  SUCCESS = 3
}

export class QrPollResult {
  status: QrPollStatus = QrPollStatus.WAITING;
  cookie: string = '';
}

class QrPollHttpResult {
  body: string = '';
  setCookie: string = '';
}

export class FolderFetchResult {
  items: BiliVideo[] = [];
  rawCount: number = 0;
  skipped: number = 0;
  partialMsg: string = '';
}

export class UpInfo {
  mid: number = 0;
  name: string = '';
  face: string = '';
}

export class SeasonMeta {
  mid: number = 0;
  name: string = '';
  total: number = 0;
  cover: string = '';
  seasonId: number = 0;
}

class CacheEntry {
  name: string = '';
  mtimeMs: number = 0;
  size: number = 0;
}


function buildHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    'Referer': REFERER,
    'User-Agent': USER_AGENT,
  };
  const session: BiliSession = BiliSession.getInstance();
  let cookie: string = session.cookieString;
  if (session.buvid3 !== '') {
    cookie = cookie === '' ? `buvid3=${session.buvid3}` : `${cookie}; buvid3=${session.buvid3}`;
  }
  if (session.buvid4 !== '') {
    cookie = cookie === '' ? `buvid4=${session.buvid4}` : `${cookie}; buvid4=${session.buvid4}`;
  }
  if (session.bNut !== '') {
    cookie = cookie === '' ? `b_nut=${session.bNut}` : `${cookie}; b_nut=${session.bNut}`;
  }
  if (cookie !== '') {
    headers['Cookie'] = cookie;
  }
  return headers;
}

function buildSpaceHeaders(mid: number): Record<string, string> {
  const headers: Record<string, string> = buildHeaders();
  headers['Referer'] = `${SPACE_ORIGIN}/${mid}`;
  headers['Origin'] = SPACE_ORIGIN;
  headers['User-Agent'] = SPACE_USER_AGENT;
  return headers;
}

// 空间投稿列表的时长字段为 'm:ss' / 'h:mm:ss' 字符串
function parseDurationLen(len: string): number {
  const parts: string[] = len.split(':');
  let seconds: number = 0;
  for (let i = 0; i < parts.length; i++) {
    seconds = seconds * 60 + (Number(parts[i]) || 0);
  }
  return seconds;
}

// US3：base64 编码（ArkTS 运行时无 btoa/Buffer，自实现标准字母表编码）
const B64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function base64EncodeBytes(bytes: Uint8Array): string {
  let out: string = '';
  for (let i: number = 0; i < bytes.length; i += 3) {
    const b0: number = bytes[i];
    const b1: number = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2: number = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += B64_ALPHABET.charAt((b0 >> 2) & 0x3F);
    out += B64_ALPHABET.charAt(((b0 & 0x3) << 4) | ((b1 >> 4) & 0x0F));
    out += i + 1 < bytes.length ? B64_ALPHABET.charAt(((b1 & 0x0F) << 2) | ((b2 >> 6) & 0x03)) : '=';
    out += i + 2 < bytes.length ? B64_ALPHABET.charAt(b2 & 0x3F) : '=';
  }
  return out;
}

// US3：dm_img 风控指纹随机串（与 PiliPlus 同源做法）——随机字节域 0x26..0x7E（避开 '%'），
// base64 后截去末 2 字符；minBytes/maxBytes 控制随机长度区间
function randomDmImgStr(minBytes: number, maxBytes: number): string {
  const span: number = maxBytes - minBytes;
  const count: number = span > 0 ? minBytes + Math.floor(Math.random() * (span + 1)) : minBytes;
  const bytes: Uint8Array = new Uint8Array(count);
  for (let i: number = 0; i < count; i++) {
    bytes[i] = 0x26 + Math.floor(Math.random() * 0x59);
  }
  return base64EncodeBytes(bytes).slice(0, -2);
}

// US3：空间投稿查询参数——在既有参数上补齐 dm_img 全套风控指纹
// （dm_img_list/dm_img_str/dm_cover_img_str/dm_img_inter/web_location/order_avoided/tid），
// 每次调用随机值刷新（PiliPlus 每次请求重新生成）
function buildUpQueryParams(mid: number): Record<string, string> {
  return {
    'mid': mid.toString(),
    'ps': '30',
    'pn': '1',
    'order': 'pubdate',
    'platform': 'web',
    'tid': '0',
    'web_location': '333.1387',
    'order_avoided': 'true',
    'dm_img_list': '[]',
    'dm_img_str': randomDmImgStr(16, 64),
    'dm_cover_img_str': randomDmImgStr(32, 128),
    'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
  };
}

// US9：日志只记 host+path，截掉可能含 cookie/token 的 query string
function logUrl(url: string): string {
  const qIdx: number = url.indexOf('?');
  return qIdx >= 0 ? url.substring(0, qIdx) : url;
}

function checkJsonBody(url: string, result: string): string {
  const trimmed: string = result.trim();
  if (trimmed === '') {
    Logger.log('error', logUrl(url), '空响应');
    throw new Error(`接口返回空响应: ${url.substring(0, 60)}`);
  }
  if (trimmed.charAt(0) !== '{' && trimmed.charAt(0) !== '[') {
    hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'non-json body: %{public}s', url.substring(0, 80));
    Logger.log('error', logUrl(url), '风控页(非JSON)');
    throw new Error('接口返回异常(疑似B站风控)，请稍后再试');
  }
  return trimmed;
}

// UP 主空间类接口（acc/info、card、arc/search）错误分类：
// -404/-400/-101/登录失效为业务性失败，立即终止降级链；
// 其余（-352/-412 风控、非 JSON 风控页、空响应、网络抖动）视为可重试错误
function isUpQueryFatal(err: Object): boolean {
  const msg: string = err instanceof Error ? err.message : String(err);
  if (msg.indexOf('登录已失效') >= 0) {
    return true;
  }
  return msg.indexOf('-404') >= 0 || msg.indexOf('-400') >= 0 || msg.indexOf('-101') >= 0;
}

function httpGet(url: string, headers: Record<string, string> | undefined = undefined): Promise<string> {
  const httpRequest: http.HttpRequest = http.createHttp();
  let logged: boolean = false; // US9：then 已记录响应码后，catch 不再重复记录
  return httpRequest.request(url, {
    method: http.RequestMethod.GET,
    header: headers === undefined ? buildHeaders() : headers,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING,
    connectTimeout: Constants.CONNECT_TIMEOUT_MS,
    readTimeout: Constants.READ_TIMEOUT_MS,
  }).then((response: http.HttpResponse) => {
    const result: string = response.result as string;
    const code: number = response.responseCode;
    httpRequest.destroy();
    Logger.log('net', logUrl(url), `HTTP ${code}`);
    logged = true;
    if (code !== 200) {
      throw new Error(`HTTP ${code}`);
    }
    return checkJsonBody(url, result);
  }).catch((err: BusinessError) => {
    httpRequest.destroy();
    if (!logged) {
      Logger.log('error', logUrl(url), err.message);
    }
    throw new Error(`HTTP request failed: ${err.message}`);
  });
}

function httpGetWithCookies(url: string): Promise<QrPollHttpResult> {
  const httpRequest: http.HttpRequest = http.createHttp();
  let logged: boolean = false; // US9：then 已记录响应码后，catch 不再重复记录
  return httpRequest.request(url, {
    method: http.RequestMethod.GET,
    header: buildHeaders(),
    usingCache: false,
    expectDataType: http.HttpDataType.STRING,
    connectTimeout: Constants.CONNECT_TIMEOUT_MS,
    readTimeout: Constants.READ_TIMEOUT_MS,
  }).then((response: http.HttpResponse) => {
    const result: string = response.result as string;
    const code: number = response.responseCode;
    let setCookie: string = '';
    const header: Record<string, Object> = response.header as Record<string, Object>;
    let sc: Object = header['set-cookie'];
    if (sc === undefined) {
      sc = header['Set-Cookie'];
    }
    if (typeof sc === 'string') {
      setCookie = sc;
    } else if (Array.isArray(sc)) {
      const arr: Object[] = sc as Object[];
      for (let i = 0; i < arr.length; i++) {
        const part: string = arr[i] as string;
        setCookie = setCookie === '' ? part : `${setCookie}\n${part}`;
      }
    }
    httpRequest.destroy();
    Logger.log('net', logUrl(url), `HTTP ${code}`);
    logged = true;
    if (code !== 200) {
      throw new Error(`HTTP ${code}`);
    }
    const out: QrPollHttpResult = new QrPollHttpResult();
    out.body = checkJsonBody(url, result);
    out.setCookie = setCookie;
    return out;
  }).catch((err: BusinessError) => {
    httpRequest.destroy();
    if (!logged) {
      Logger.log('error', logUrl(url), err.message);
    }
    throw new Error(`HTTP request failed: ${err.message}`);
  });
}

function httpPostForm(url: string, body: string): Promise<string> {
  const httpRequest: http.HttpRequest = http.createHttp();
  const headers: Record<string, string> = buildHeaders();
  let logged: boolean = false; // US9：then 已记录响应码后，catch 不再重复记录
  headers['Content-Type'] = 'application/x-www-form-urlencoded';
  return httpRequest.request(url, {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: body,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING,
    connectTimeout: Constants.CONNECT_TIMEOUT_MS,
    readTimeout: Constants.READ_TIMEOUT_MS,
  }).then((response: http.HttpResponse) => {
    const result: string = response.result as string;
    const code: number = response.responseCode;
    httpRequest.destroy();
    Logger.log('net', logUrl(url), `HTTP ${code}`);
    logged = true;
    if (code !== 200) {
      throw new Error(`HTTP ${code}`);
    }
    return checkJsonBody(url, result);
  }).catch((err: BusinessError) => {
    httpRequest.destroy();
    if (!logged) {
      Logger.log('error', logUrl(url), err.message);
    }
    throw new Error(`HTTP request failed: ${err.message}`);
  });
}

function parseApiData(resultStr: string): Record<string, Object> {
  const root: Record<string, Object> = JSON.parse(resultStr) as Record<string, Object>;
  const code: number = root['code'] as number;
  if (code !== 0) {
    if (code === -101) {
      throw new Error('登录已失效，请在设置中重新登录');
    }
    throw new Error(`Bili API error ${code}`);
  }
  return root['data'] as Record<string, Object>;
}

function cleanTitle(title: string): string {
  let t: string = title;
  t = t.split('<em class="keyword">').join('');
  t = t.split('</em>').join('');
  return t;
}

function isValidMediaFile(localPath: string): boolean {
  try {
    const stat: fs.Stat = fs.statSync(localPath);
    if (stat.size < 1024) {
      return false;
    }
    const file: fs.File = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
    try {
      const buf: ArrayBuffer = new ArrayBuffer(12);
      fs.readSync(file.fd, buf);
      const bytes: Uint8Array = new Uint8Array(buf);
      const tag: string = String.fromCharCode(bytes[4], bytes[5], bytes[6], bytes[7]);
      return tag === 'ftyp';
    } finally {
      fs.closeSync(file);
    }
  } catch (e) {
    return false;
  }
}

function isMediaCacheName(name: string): boolean {
  return name.endsWith('.m4a') || name.endsWith('.mp4');
}

export class BiliService {
  static async fetchNav(): Promise<void> {
    const resultStr: string = await httpGet(BILI_NAV_URL);
    const data: Record<string, Object> = JSON.parse(resultStr) as Record<string, Object>;
    const code: number = data['code'] as number;
    if (code !== 0) {
      BiliSession.getInstance().clear();
      throw new Error('登录已失效，请在设置中重新登录');
    }
    const payload: Record<string, Object> = data['data'] as Record<string, Object>;
    const isLogin: boolean = payload['isLogin'] as boolean;
    if (!isLogin) {
      BiliSession.getInstance().clear();
      throw new Error('Cookie无效，请重新登录');
    }
    const session: BiliSession = BiliSession.getInstance();
    session.mid = payload['mid'] as number;
    session.uname = payload['uname'] as string;
  }


  private static normalizeCover(rec: Record<string, Object>): string {
    let url: string = '';
    const coverRaw: Object = rec['cover'];
    if (coverRaw !== undefined && coverRaw !== null && (coverRaw as string) !== '') {
      url = coverRaw as string;
    } else {
      const picRaw: Object = rec['pic'];
      if (picRaw !== undefined && picRaw !== null && (picRaw as string) !== '') {
        url = picRaw as string;
      }
    }
    if (url.startsWith('http://')) {
      url = 'https://' + url.substring(7);
    }
    return url;
  }

  // ponytail: mixinKey 内存缓存（按天失效 + 单飞）；天花板——进程重启后重取、当天 key 失效需次日轮换（与 Web 端一致）
  private static mixinKeyCache: string = '';
  private static mixinKeyCacheDay: number = -1;
  private static mixinKeyPromise: Promise<string> | undefined = undefined;

  private static async fetchMixinKey(): Promise<string> {
    const day: number = Math.floor(Date.now() / 86400000);
    if (BiliService.mixinKeyCache !== '' && BiliService.mixinKeyCacheDay === day) {
      return BiliService.mixinKeyCache;
    }
    if (BiliService.mixinKeyPromise !== undefined) {
      return BiliService.mixinKeyPromise;
    }
    const pending: Promise<string> = BiliService.fetchMixinKeyUncached().then((key: string): string => {
      BiliService.mixinKeyCache = key;
      BiliService.mixinKeyCacheDay = day;
      BiliService.mixinKeyPromise = undefined;
      return key;
    }).catch((err: BusinessError): string => {
      BiliService.mixinKeyPromise = undefined;
      throw new Error(err.message);
    });
    BiliService.mixinKeyPromise = pending;
    return pending;
  }

  private static async fetchMixinKeyUncached(): Promise<string> {
    await BiliService.ensureBuvid();
    const navStr: string = await httpGet(BILI_NAV_URL);
    const navRoot: Record<string, Object> = JSON.parse(navStr) as Record<string, Object>;
    const navData: Record<string, Object> = navRoot['data'] as Record<string, Object>;
    const wbiImgRaw: Object = navData['wbi_img'];
    if (wbiImgRaw === undefined || wbiImgRaw === null) {
      throw new Error('nav 接口未返回 wbi_img');
    }
    const wbiImg: Record<string, Object> = wbiImgRaw as Record<string, Object>;
    const imgUrl: string = wbiImg['img_url'] as string;
    const subUrl: string = wbiImg['sub_url'] as string;
    return WbiSigner.getMixinKey(imgUrl, subUrl);
  }

  static async fetchSeasonsList(mid: number): Promise<Season[]> {
    const mixinKey: string = await BiliService.fetchMixinKey();
    const params: Record<string, string> = {
      'mid': mid.toString(),
      'page_num': '1',
      'page_size': '20',
    };
    const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
    const resultStr: string = await httpGet(`${BILI_SEASONS_SERIES_LIST_URL}?${signedQuery}`);
    const data: Record<string, Object> = parseApiData(resultStr);
    const seasons: Season[] = [];
    const itemsListsRaw: Object = data['items_lists'];
    if (itemsListsRaw !== undefined && itemsListsRaw !== null) {
      const itemsLists: Record<string, Object> = itemsListsRaw as Record<string, Object>;
      const seasonsRaw: Object = itemsLists['seasons_list'];
      if (seasonsRaw !== undefined && seasonsRaw !== null) {
        const arr: Object[] = seasonsRaw as Object[];
        for (let i = 0; i < arr.length; i++) {
          const rec: Record<string, Object> = arr[i] as Record<string, Object>;
          let seasonId: number = 0;
          const topSeasonIdRaw: Object = rec['season_id'];
          if (topSeasonIdRaw !== undefined && topSeasonIdRaw !== null) {
            seasonId = topSeasonIdRaw as number;
          }
          let title: string = '';
          let count: number = 0;
          let cover: string = '';
          const metaRaw: Object = rec['meta'];
          if (metaRaw !== undefined && metaRaw !== null) {
            const meta: Record<string, Object> = metaRaw as Record<string, Object>;
            if (seasonId === 0 && meta['season_id'] !== undefined && meta['season_id'] !== null) {
              seasonId = meta['season_id'] as number;
            }
            const nameRaw: Object = meta['name'];
            if (nameRaw !== undefined && nameRaw !== null) {
              title = cleanTitle(nameRaw as string);
            }
            const totalRaw: Object = meta['total'];
            if (totalRaw !== undefined && totalRaw !== null) {
              count = totalRaw as number;
            }
            const coverRaw: Object = meta['cover'];
            if (coverRaw !== undefined && coverRaw !== null) {
              cover = coverRaw as string;
            }
          }
          if (seasonId === 0) {
            continue;
          }
          seasons.push(new Season(seasonId, title, count, cover));
        }
      }
    }
    return seasons;
  }

  // UP 主的「系列」列表；ponytail: 复用 Season 类，seasonId 字段承载 series_id
  static async fetchSeriesList(mid: number): Promise<Season[]> {
    const mixinKey: string = await BiliService.fetchMixinKey();
    const params: Record<string, string> = {
      'mid': mid.toString(),
      'page_num': '1',
      'page_size': '20',
    };
    const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
    const resultStr: string = await httpGet(`${BILI_SEASONS_SERIES_LIST_URL}?${signedQuery}`);
    const data: Record<string, Object> = parseApiData(resultStr);
    const series: Season[] = [];
    const itemsListsRaw: Object = data['items_lists'];
    if (itemsListsRaw !== undefined && itemsListsRaw !== null) {
      const itemsLists: Record<string, Object> = itemsListsRaw as Record<string, Object>;
      const seriesRaw: Object = itemsLists['series_list'];
      if (seriesRaw !== undefined && seriesRaw !== null) {
        const arr: Object[] = seriesRaw as Object[];
        for (let i = 0; i < arr.length; i++) {
          const rec: Record<string, Object> = arr[i] as Record<string, Object>;
          let seriesId: number = 0;
          const seriesIdRaw: Object = rec['series_id'];
          if (seriesIdRaw !== undefined && seriesIdRaw !== null) {
            seriesId = seriesIdRaw as number;
          }
          let title: string = '';
          let count: number = 0;
          let cover: string = '';
          const metaRaw: Object = rec['meta'];
          if (metaRaw !== undefined && metaRaw !== null) {
            const meta: Record<string, Object> = metaRaw as Record<string, Object>;
            const nameRaw: Object = meta['name'];
            if (nameRaw !== undefined && nameRaw !== null) {
              title = cleanTitle(nameRaw as string);
            }
            const totalRaw: Object = meta['total'];
            if (totalRaw !== undefined && totalRaw !== null) {
              count = totalRaw as number;
            }
            const coverRaw: Object = meta['cover'];
            if (coverRaw !== undefined && coverRaw !== null) {
              cover = coverRaw as string;
            }
          }
          if (seriesId === 0) {
            continue;
          }
          series.push(new Season(seriesId, title, count, cover));
        }
      }
    }
    return series;
  }

  // seasons_archives_list / series archives 共用的条目解析（合集接口为正序，最老在前）
  private static parseArchiveRecords(archives: Object[]): BiliVideo[] {
    const items: BiliVideo[] = [];
    for (let i = 0; i < archives.length; i++) {
      const rec: Record<string, Object> = archives[i] as Record<string, Object>;
      const bvidRaw: Object = rec['bvid'];
      const bvid: string = bvidRaw === undefined || bvidRaw === null ? '' : bvidRaw as string;
      if (bvid === '') {
        continue;
      }
      const item: BiliVideo = new BiliVideo();
      item.bvid = bvid;
      if (rec['aid'] !== undefined && rec['aid'] !== null) {
        item.aid = rec['aid'] as number;
      }
      const titleRaw: Object = rec['title'];
      item.title = titleRaw === undefined || titleRaw === null ? '' : cleanTitle(titleRaw as string);
      item.cover = BiliService.normalizeCover(rec);
      if (rec['duration'] !== undefined && rec['duration'] !== null) {
        item.duration = rec['duration'] as number;
      }
      if (rec['pubdate'] !== undefined && rec['pubdate'] !== null) {
        item.pubdate = rec['pubdate'] as number;
      }
      const ownerRaw: Object = rec['owner'];
      if (ownerRaw !== undefined && ownerRaw !== null) {
        const owner: Record<string, Object> = ownerRaw as Record<string, Object>;
        if (owner['mid'] !== undefined && owner['mid'] !== null) {
          item.ownerMid = owner['mid'] as number;
        }
        if (owner['name'] !== undefined && owner['name'] !== null) {
          item.ownerName = owner['name'] as string;
        }
      }
      items.push(item);
    }
    return items;
  }

  // maxPages/sortReverse：默认值保持旧行为（全量、正序）；订阅刷新传 (1, true) 只取最新一页
  static async fetchSeasonVideos(mid: number, seasonId: number,
    maxPages: number = 200, sortReverse: boolean = false): Promise<BiliVideo[]> {
    const items: BiliVideo[] = [];
    const ps: number = 20;
    let pn: number = 1;
    while (pn <= maxPages) {
      const mixinKey: string = await BiliService.fetchMixinKey();
      const params: Record<string, string> = {
        'mid': mid.toString(),
        'season_id': seasonId.toString(),
        'sort_reverse': sortReverse ? 'true' : 'false',
        'page_num': pn.toString(),
        'page_size': ps.toString(),
      };
      const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
      const resultStr: string = await httpGet(`${BILI_SEASONS_ARCHIVES_LIST_URL}?${signedQuery}`);
      const data: Record<string, Object> = parseApiData(resultStr);
      const archivesRaw: Object = data['archives'];
      let archives: Object[] = [];
      if (archivesRaw !== undefined && archivesRaw !== null) {
        archives = archivesRaw as Object[];
      }
      const parsed: BiliVideo[] = BiliService.parseArchiveRecords(archives);
      for (let i = 0; i < parsed.length; i++) {
        items.push(parsed[i]);
      }
      let total: number = 0;
      const pageRaw: Object = data['page'];
      if (pageRaw !== undefined && pageRaw !== null) {
        const page: Record<string, Object> = pageRaw as Record<string, Object>;
        const totalRaw: Object = page['total'];
        if (totalRaw !== undefined && totalRaw !== null) {
          total = totalRaw as number;
        }
      }
      if (archives.length < ps) {
        break;
      }
      if (total > 0 && items.length >= total) {
        break;
      }
      pn++;
      if (pn <= maxPages) {
        await sleep(1500);
      }
    }
    return items;
  }

  // maxPages/sortReverse：默认值保持旧行为（全量、正序）；订阅刷新传 (1, true) 只取最新一页
  static async fetchSeriesVideos(mid: number, seriesId: number,
    maxPages: number = 200, sortReverse: boolean = false): Promise<BiliVideo[]> {
    const items: BiliVideo[] = [];
    const ps: number = 30;
    let pn: number = 1;
    while (pn <= maxPages) {
      const mixinKey: string = await BiliService.fetchMixinKey();
      const params: Record<string, string> = {
        'mid': mid.toString(),
        'series_id': seriesId.toString(),
        'only_mid': 'true',
        'sort_reverse': sortReverse ? 'true' : 'false',
        'pn': pn.toString(),
        'ps': ps.toString(),
      };
      const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
      const resultStr: string = await httpGet(`${BILI_SERIES_ARCHIVES_URL}?${signedQuery}`);
      const data: Record<string, Object> = parseApiData(resultStr);
      const archivesRaw: Object = data['archives'];
      let archives: Object[] = [];
      if (archivesRaw !== undefined && archivesRaw !== null) {
        archives = archivesRaw as Object[];
      }
      const parsed: BiliVideo[] = BiliService.parseArchiveRecords(archives);
      for (let i = 0; i < parsed.length; i++) {
        items.push(parsed[i]);
      }
      let total: number = 0;
      const pageRaw: Object = data['page'];
      if (pageRaw !== undefined && pageRaw !== null) {
        const page: Record<string, Object> = pageRaw as Record<string, Object>;
        const totalRaw: Object = page['total'];
        if (totalRaw !== undefined && totalRaw !== null) {
          total = totalRaw as number;
        }
      }
      if (archives.length < ps) {
        break;
      }
      if (total > 0 && items.length >= total) {
        break;
      }
      pn++;
      if (pn <= maxPages) {
        await sleep(1500);
      }
    }
    return items;
  }

  // US3：APP 端点投稿查询（app.bilibili.com BiliDroid 渠道）——无 cookie/WBI 依赖，
  // 未登录亦可靠查询；仅携带 BiliDroid UA
  private static async fetchUpVideosViaApp(mid: number): Promise<BiliVideo[]> {
    const params: Record<string, string> = {
      'vmid': mid.toString(),
      'ps': '30',
      'pn': '1',
      'build': '8430300',
      'mobi_app': 'android',
      'platform': 'android',
    };
    const headers: Record<string, string> = {
      'User-Agent': Constants.BILI_APP_USER_AGENT,
    };
    const resultStr: string = await BiliService.fetchUpVideosOnce(
      Constants.BILI_APP_ARCHIVE_URL, params, headers);
    return BiliService.parseAppArchiveList(resultStr, mid);
  }

  // US3：APP 端点响应解析——真实 BiliDroid 响应为 data.item[]（author/play/duration 为顶层字段、
  // aid 以字符串 param 透出），兼容 data.archives[]（owner{}/stat{} 嵌套）命名；
  // title 经 cleanTitle、cover 经 normalizeCover 规范化
  private static parseAppArchiveList(resultStr: string, mid: number): BiliVideo[] {
    const root: Record<string, Object> = JSON.parse(resultStr) as Record<string, Object>;
    const code: number = root['code'] as number;
    if (code !== 0) {
      // 透出真实错误码，供降级链分类与上层提示
      throw new Error(`Bili API error ${code}`);
    }
    const data: Record<string, Object> = root['data'] as Record<string, Object>;
    const items: BiliVideo[] = [];
    let arrRaw: Object = data['item'];
    if (arrRaw === undefined || arrRaw === null) {
      arrRaw = data['archives'];
    }
    if (arrRaw === undefined || arrRaw === null) {
      return items;
    }
    const arr: Object[] = arrRaw as Object[];
    for (let i: number = 0; i < arr.length; i++) {
      const rec: Record<string, Object> = arr[i] as Record<string, Object>;
      const bvidRaw: Object = rec['bvid'];
      const bvid: string = bvidRaw === undefined || bvidRaw === null ? '' : bvidRaw as string;
      if (bvid === '') {
        continue;
      }
      const item: BiliVideo = new BiliVideo();
      item.bvid = bvid;
      // aid：整数 aid 或字符串 param
      const aidRaw: Object = rec['aid'];
      if (aidRaw !== undefined && aidRaw !== null) {
        item.aid = Number(aidRaw);
      } else {
        const paramRaw: Object = rec['param'];
        if (paramRaw !== undefined && paramRaw !== null) {
          item.aid = Number(paramRaw);
        }
      }
      const titleRaw: Object = rec['title'];
      item.title = titleRaw === undefined || titleRaw === null ? '' : cleanTitle(titleRaw as string);
      item.cover = BiliService.normalizeCover(rec);
      // duration：APP 端点为秒（可能为 -1），Web 兼容 'm:ss' 字符串
      const durRaw: Object = rec['duration'];
      if (durRaw !== undefined && durRaw !== null) {
        if (typeof durRaw === 'number') {
          const dur: number = durRaw as number;
          item.duration = dur > 0 ? dur : 0;
        } else {
          item.duration = parseDurationLen(durRaw as string);
        }
      }
      // pubdate：APP 端点为 pubdate，Web 兼容 created
      const pubRaw: Object = rec['pubdate'];
      if (pubRaw !== undefined && pubRaw !== null) {
        item.pubdate = Number(pubRaw);
      } else {
        const createdRaw: Object = rec['created'];
        if (createdRaw !== undefined && createdRaw !== null) {
          item.pubdate = Number(createdRaw);
        }
      }
      // UP 主：APP item[] 为顶层 author/mid；Web archives[] 为 owner{mid,name,face}
      const ownerRaw: Object = rec['owner'];
      if (ownerRaw !== undefined && ownerRaw !== null) {
        const owner: Record<string, Object> = ownerRaw as Record<string, Object>;
        const ownerMidRaw: Object = owner['mid'];
        item.ownerMid = ownerMidRaw === undefined || ownerMidRaw === null ? mid : Number(ownerMidRaw);
        const ownerNameRaw: Object = owner['name'];
        item.ownerName = ownerNameRaw === undefined || ownerNameRaw === null ? '' : ownerNameRaw as string;
        const ownerFaceRaw: Object = owner['face'];
        item.ownerFace = ownerFaceRaw === undefined || ownerFaceRaw === null ? '' : ownerFaceRaw as string;
      } else {
        item.ownerMid = mid;
        const authorRaw: Object = rec['author'];
        if (authorRaw !== undefined && authorRaw !== null) {
          item.ownerName = authorRaw as string;
        }
      }
      // 播放量：Web archives[] 为 stat.view；APP item[] 为顶层 play
      const statRaw: Object = rec['stat'];
      if (statRaw !== undefined && statRaw !== null) {
        const stat: Record<string, Object> = statRaw as Record<string, Object>;
        const viewRaw: Object = stat['view'];
        if (viewRaw !== undefined && viewRaw !== null) {
          item.view = Number(viewRaw);
        }
      } else {
        const playRaw: Object = rec['play'];
        if (playRaw !== undefined && playRaw !== null) {
          item.view = Number(playRaw);
        }
      }
      items.push(item);
    }
    return items;
  }

  // UP 主最新投稿（单页 30 条，新集在前）
  // ponytail: 只取第一页——播客「近期节目」语义；升级路径：SourcePage 滚动到底按需追加页
  // 风控降级链（US3）：APP 端点优先（BiliDroid 渠道，无 cookie/WBI），失败降级 Web 链——
  // 最多 3 轮，每轮「无签名 arc/search → WBI 签名」两步；
  // -352/-412/风控页/网络错误等可重试错误重置 buvid 指数退避后进下一轮，
  // -404/-400/-101 等业务错误立即失败；全败时抛出最后一轮真实错误（含错误码）
  static async fetchUpVideos(mid: number): Promise<BiliVideo[]> {
    // US3：APP 端点优先——BiliDroid 渠道不依赖 cookie/WBI，未登录查询首选；
    // 业务性失败（-404/-400/-101）直接透出，风控/网络错误降级 Web 链
    try {
      const appItems: BiliVideo[] = await BiliService.fetchUpVideosViaApp(mid);
      Logger.log('net', 'UP投稿列表', `APP端点成功 mid=${mid} count=${appItems.length}`);
      return appItems;
    } catch (appErr) {
      const appError: Error = appErr instanceof Error ? appErr : new Error(String(appErr));
      Logger.log('error', 'UP投稿列表', `APP端点失败 mid=${mid}: ${appError.message}`);
      if (isUpQueryFatal(appError)) {
        throw appError;
      }
    }

    const spaceHeaders: Record<string, string> = buildSpaceHeaders(mid);
    let lastError: Error = new Error('查询UP主投稿失败');
    for (let attempt: number = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        BiliSession.getInstance().resetBuvid();
        await sleep(2000 * attempt);
      }
      // US3：每轮注入全套 dm_img 风控指纹参数（随机值按轮刷新）
      const params: Record<string, string> = buildUpQueryParams(mid);
      try {
        const plainResult: string = await BiliService.fetchUpVideosOnce(`${BILI_SPACE_ARC_URL}`, params, spaceHeaders);
        Logger.log('net', 'UP投稿列表', `第${attempt + 1}轮直连成功 mid=${mid}`);
        return BiliService.parseUpVideoList(plainResult);
      } catch (plainErr) {
        const plainError: Error = plainErr instanceof Error ? plainErr : new Error(String(plainErr));
        lastError = plainError;
        Logger.log('error', 'UP投稿列表', `第${attempt + 1}轮直连失败 mid=${mid}: ${plainError.message}`);
        if (isUpQueryFatal(plainError)) {
          throw plainError;
        }
      }
      try {
        const mixinKey: string = await BiliService.fetchMixinKey();
        const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
        const wbiResult: string = await BiliService.fetchUpVideosOnce(
          `${BILI_SPACE_ARC_SEARCH_URL}?${signedQuery}`, {}, spaceHeaders);
        Logger.log('net', 'UP投稿列表', `第${attempt + 1}轮WBI成功 mid=${mid}`);
        return BiliService.parseUpVideoList(wbiResult);
      } catch (wbiErr) {
        const wbiError: Error = wbiErr instanceof Error ? wbiErr : new Error(String(wbiErr));
        lastError = wbiError;
        Logger.log('error', 'UP投稿列表', `第${attempt + 1}轮WBI失败 mid=${mid}: ${wbiError.message}`);
        if (isUpQueryFatal(wbiError)) {
          throw wbiError;
        }
      }
    }
    Logger.log('error', 'UP投稿列表', `3轮均失败 mid=${mid}: ${lastError.message}`);
    throw lastError;
  }

  private static async fetchUpVideosOnce(
    url: string, params: Record<string, string>,
    headers: Record<string, string>): Promise<string> {
    const query: string = Object.keys(params).length > 0
      ? '?' + Object.keys(params).map((k: string): string =>
        `${k}=${encodeURIComponent(params[k])}`).join('&')
      : '';
    return await httpGet(`${url}${query}`, headers);
  }

  private static parseUpVideoList(resultStr: string): BiliVideo[] {
    const root: Record<string, Object> = JSON.parse(resultStr) as Record<string, Object>;
    const code: number = root['code'] as number;
    if (code !== 0) {
      // 透出真实错误码（如 -352/-412 风控），供降级链分类与上层提示
      throw new Error(`Bili API error ${code}`);
    }
    const data: Record<string, Object> = root['data'] as Record<string, Object>;
    const items: BiliVideo[] = [];
    const listRaw: Object = data['list'];
    if (listRaw !== undefined && listRaw !== null) {
      const list: Record<string, Object> = listRaw as Record<string, Object>;
      const vlistRaw: Object = list['vlist'];
      if (vlistRaw !== undefined && vlistRaw !== null) {
        const arr: Object[] = vlistRaw as Object[];
        for (let i: number = 0; i < arr.length; i++) {
          const rec: Record<string, Object> = arr[i] as Record<string, Object>;
          const bvidRaw: Object = rec['bvid'];
          const bvid: string = bvidRaw === undefined || bvidRaw === null ? '' : bvidRaw as string;
          if (bvid === '') {
            continue;
          }
          const item: BiliVideo = new BiliVideo();
          item.bvid = bvid;
          if (rec['aid'] !== undefined && rec['aid'] !== null) {
            item.aid = rec['aid'] as number;
          }
          const titleRaw: Object = rec['title'];
          item.title = titleRaw === undefined || titleRaw === null ? '' : cleanTitle(titleRaw as string);
          item.cover = BiliService.normalizeCover(rec);
          const lenRaw: Object = rec['length'];
          item.duration = lenRaw === undefined || lenRaw === null ? 0 : parseDurationLen(lenRaw as string);
          if (rec['created'] !== undefined && rec['created'] !== null) {
            item.pubdate = rec['created'] as number;
          }
          if (rec['mid'] !== undefined && rec['mid'] !== null) {
            item.ownerMid = rec['mid'] as number;
          }
          if (rec['author'] !== undefined && rec['author'] !== null) {
            item.ownerName = rec['author'] as string;
          }
          items.push(item);
        }
      }
    }
    return items;
  }

  static async resolveShortUrl(shortUrl: string): Promise<string> {
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(shortUrl, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': USER_AGENT,
          'Referer': REFERER,
        },
        usingCache: false,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: Constants.CONNECT_TIMEOUT_MS,
        readTimeout: Constants.READ_TIMEOUT_MS,
      });
      httpRequest.destroy();
      const body: string = response.result as string;
      Logger.log('net', logUrl(shortUrl), `HTTP ${response.responseCode}`);
      const bvMatch: RegExpMatchArray | null = body.match(/BV[0-9A-Za-z]{10}/);
      if (bvMatch !== null) {
        return `https://www.bilibili.com/video/${bvMatch[0]}`;
      }
      const urlMatch: RegExpMatchArray | null = body.match(/https?:\/\/(?:www\.)?bilibili\.com\/[^\s"'<>]+/);
      if (urlMatch !== null) {
        return urlMatch[0];
      }
      return shortUrl;
    } catch (_err) {
      httpRequest.destroy();
      Logger.log('error', logUrl(shortUrl), '短链解析失败');
      return shortUrl;
    }
  }

  static async fetchUpInfo(mid: number): Promise<UpInfo> {
    const params: Record<string, string> = {
      'mid': mid.toString(),
    };
    let lastError: Error = new Error('查询UP主失败');
    // acc/info 风控严格（-352 频发）：最多 3 轮「WBI 签名 acc/info → card 兜底」降级；
    // -352/-412/风控页等可重试错误重置 buvid 指数退避后进下一轮，
    // -404/-400/-101 等业务错误立即失败；全败时抛出最后一轮真实错误（含错误码）
    for (let attempt: number = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        BiliSession.getInstance().resetBuvid();
        await sleep(2000 * attempt);
      }
      try {
        const mixinKey: string = await BiliService.fetchMixinKey();
        const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
        try {
          const resultStr: string = await httpGet(`${BILI_SPACE_ACC_INFO_URL}?${signedQuery}`, buildSpaceHeaders(mid));
          Logger.log('net', 'UP主信息', `第${attempt + 1}轮acc/info成功 mid=${mid}`);
          return BiliService.parseUpInfo(parseApiData(resultStr), mid);
        } catch (accErr) {
          const accError: Error = accErr instanceof Error ? accErr : new Error(String(accErr));
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG,
            'acc/info failed (mid=%{public}d, attempt %{public}d): %{public}s, fallback to card',
            mid, attempt + 1, accError.message);
          Logger.log('error', 'UP主信息', `第${attempt + 1}轮acc/info失败 mid=${mid}: ${accError.message}`);
          if (isUpQueryFatal(accError)) {
            throw accError;
          }
          // card 接口风控宽松，兜底取 name/face
          const cardStr: string = await httpGet(`${BILI_CARD_URL}?${signedQuery}`, buildSpaceHeaders(mid));
          const data: Record<string, Object> = parseApiData(cardStr);
          const cardRaw: Object = data['card'];
          if (cardRaw === undefined || cardRaw === null) {
            throw new Error('未获取到UP主信息');
          }
          Logger.log('net', 'UP主信息', `第${attempt + 1}轮card兜底成功 mid=${mid}`);
          return BiliService.parseUpInfo(cardRaw as Record<string, Object>, mid);
        }
      } catch (roundErr) {
        const roundError: Error = roundErr instanceof Error ? roundErr : new Error(String(roundErr));
        lastError = roundError;
        if (isUpQueryFatal(roundError)) {
          throw roundError;
        }
      }
    }
    Logger.log('error', 'UP主信息', `3轮均失败 mid=${mid}: ${lastError.message}`);
    throw lastError;
  }

  // acc/info 与 card 的用户字段结构一致（name/face 同名）
  private static parseUpInfo(data: Record<string, Object>, mid: number): UpInfo {
    const info: UpInfo = new UpInfo();
    info.mid = mid;
    if (data['name'] !== undefined && data['name'] !== null) {
      info.name = data['name'] as string;
    }
    if (data['face'] !== undefined && data['face'] !== null) {
      info.face = data['face'] as string;
    }
    if (info.name === '') {
      throw new Error('未获取到UP主信息');
    }
    return info;
  }

  static async fetchSeasonMeta(seasonId: number): Promise<SeasonMeta> {
    const mixinKey: string = await BiliService.fetchMixinKey();
    const params: Record<string, string> = {
      'season_id': seasonId.toString(),
      'page_num': '1',
      'page_size': '1',
    };
    const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
    const resultStr: string = await httpGet(`${BILI_SEASONS_ARCHIVES_LIST_URL}?${signedQuery}`);
    const data: Record<string, Object> = parseApiData(resultStr);
    const meta: SeasonMeta = new SeasonMeta();
    meta.seasonId = seasonId;
    const metaRaw: Object = data['meta'];
    if (metaRaw !== undefined && metaRaw !== null) {
      const rec: Record<string, Object> = metaRaw as Record<string, Object>;
      if (rec['mid'] !== undefined && rec['mid'] !== null) {
        meta.mid = rec['mid'] as number;
      }
      if (rec['name'] !== undefined && rec['name'] !== null) {
        meta.name = cleanTitle(rec['name'] as string);
      }
      if (rec['total'] !== undefined && rec['total'] !== null) {
        meta.total = rec['total'] as number;
      }
      if (rec['cover'] !== undefined && rec['cover'] !== null) {
        meta.cover = rec['cover'] as string;
      }
    }
    if (meta.name === '') {
      meta.name = `合集 ${seasonId}`;
    }
    return meta;
  }

  static async fetchSeriesMeta(seriesId: number): Promise<SeasonMeta> {
    const mixinKey: string = await BiliService.fetchMixinKey();
    const params: Record<string, string> = {
      'series_id': seriesId.toString(),
    };
    const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
    const resultStr: string = await httpGet(`${BILI_SERIES_META_URL}?${signedQuery}`);
    const data: Record<string, Object> = parseApiData(resultStr);
    const meta: SeasonMeta = new SeasonMeta();
    const metaRaw: Object = data['meta'];
    if (metaRaw !== undefined && metaRaw !== null) {
      const rec: Record<string, Object> = metaRaw as Record<string, Object>;
      if (rec['mid'] !== undefined && rec['mid'] !== null) {
        meta.mid = rec['mid'] as number;
      }
      if (rec['name'] !== undefined && rec['name'] !== null) {
        meta.name = cleanTitle(rec['name'] as string);
      }
      if (rec['total'] !== undefined && rec['total'] !== null) {
        meta.total = rec['total'] as number;
      }
      if (rec['cover'] !== undefined && rec['cover'] !== null) {
        meta.cover = rec['cover'] as string;
      }
      if (rec['series_id'] !== undefined && rec['series_id'] !== null) {
        meta.seasonId = rec['series_id'] as number;
      }
    }
    if (meta.seasonId === 0) {
      meta.seasonId = seriesId;
    }
    if (meta.name === '') {
      meta.name = `系列 ${seriesId}`;
    }
    return meta;
  }

  static async fetchMyFolders(): Promise<FavFolder[]> {
    const session: BiliSession = BiliSession.getInstance();
    if (!session.isLogged()) {
      throw new Error('请先登录B站账号');
    }
    if (session.mid === 0) {
      await BiliService.fetchNav();
    }
    const resultStr: string = await httpGet(`${BILI_FAV_FOLDERS_URL}?up_mid=${session.mid}&type=0`);
    const data: Record<string, Object> = parseApiData(resultStr);
    const folders: FavFolder[] = [];
    if (data['list'] !== undefined) {
      const list: Object[] = data['list'] as Object[];
      for (let i = 0; i < list.length; i++) {
        const rec: Record<string, Object> = list[i] as Record<string, Object>;
        folders.push(new FavFolder(
          rec['id'] as number,
          cleanTitle(rec['title'] as string),
          rec['media_count'] as number,
        ));
      }
    }
    return folders;
  }

  // maxPages：默认全量；订阅刷新传 1 只取最新一页（播客「近期节目」语义）
  static async fetchFolderVideos(mediaId: number, totalCount: number,
    onProgress: PageProgressCallback | undefined, maxPages: number = 200): Promise<FolderFetchResult> {
    const result: FolderFetchResult = new FolderFetchResult();
    const ps: number = 20;
    let pn: number = 1;
    let emptyRounds: number = 0;
    while (pn <= maxPages) {
      let data: Record<string, Object> | undefined = undefined;
      let lastErrMsg: string = '';
      for (let attempt = 0; attempt < 4 && data === undefined; attempt++) {
        if (attempt > 0) {
          await sleep(lastErrMsg.indexOf('412') >= 0 ? 15000 * attempt : 2000 * attempt);
        }
        try {
          const resultStr: string = await httpGet(
            `${BILI_FAV_RESOURCE_URL}?media_id=${mediaId}&pn=${pn}&ps=${ps}` +
            `&keyword=&order=mtime&type=2&tid=0&platform=web`
          );
          data = parseApiData(resultStr);
        } catch (err) {
          const error = err as BusinessError;
          lastErrMsg = error.message;
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'folder page failed (attempt %{public}d): %{public}s', attempt + 1, lastErrMsg);
        }
      }
      if (data === undefined) {
        if (result.rawCount > 0) {
          result.partialMsg = `部分内容获取失败(${lastErrMsg})`;
          break;
        }
        throw new Error(`获取收藏夹内容失败: ${lastErrMsg}`);
      }
      const mediasRaw: Object = data['medias'];
      if (mediasRaw === undefined || mediasRaw === null) {
        break;
      }
      const medias: Object[] = mediasRaw as Object[];
      for (let i = 0; i < medias.length; i++) {
        const rec: Record<string, Object> = medias[i] as Record<string, Object>;
        const bvid: string = rec['bvid'] as string;
        if (bvid === '' || bvid === undefined || rec['id'] === undefined) {
          result.skipped++;
          continue;
        }
        const attrRaw: Object = rec['attr'];
        const attr: number = attrRaw === undefined || attrRaw === null ? 0 : attrRaw as number;
        const rawTitle: Object = rec['title'];
        const titleStr: string = rawTitle === undefined || rawTitle === null ? '' : rawTitle as string;
        if ((attr & 1) !== 0 || titleStr === '已失效视频') {
          result.skipped++;
          continue;
        }
        const item: BiliVideo = new BiliVideo();
        item.bvid = bvid;
        item.aid = rec['id'] as number;
        item.title = cleanTitle(rec['title'] as string);
        item.cover = rec['cover'] as string;
        item.duration = rec['duration'] as number;
        const upperRaw: Object = rec['upper'];
        if (upperRaw !== undefined && upperRaw !== null) {
          const upper: Record<string, Object> = upperRaw as Record<string, Object>;
          if (upper['mid'] !== undefined) {
            item.ownerMid = upper['mid'] as number;
          }
          if (upper['name'] !== undefined) {
            item.ownerName = upper['name'] as string;
          }
          if (upper['face'] !== undefined) {
            item.ownerFace = upper['face'] as string;
          }
        }
        const introRaw: Object = rec['intro'];
        if (introRaw !== undefined && introRaw !== null) {
          item.desc = introRaw as string;
        }
        const pubtimeRaw: Object = rec['pubtime'];
        if (pubtimeRaw !== undefined && pubtimeRaw !== null) {
          item.pubdate = pubtimeRaw as number;
        }
        const cntRaw: Object = rec['cnt_info'];
        if (cntRaw !== undefined && cntRaw !== null) {
          const cnt: Record<string, Object> = cntRaw as Record<string, Object>;
          const playRaw: Object = cnt['play'];
          if (playRaw !== undefined && playRaw !== null) {
            item.view = playRaw as number;
          }
        }
        result.items.push(item);
      }
      result.rawCount += medias.length;
      if (onProgress !== undefined) {
        onProgress(result.rawCount, totalCount);
      }
      const hasMoreRaw: Object = data['has_more'];
      const hasMore: boolean = hasMoreRaw === undefined ? false : Boolean(hasMoreRaw);
      if (!hasMore) {
        break;
      }
      if (medias.length === 0) {
        emptyRounds++;
        if (emptyRounds >= 2) {
          break;
        }
      } else {
        emptyRounds = 0;
      }
      pn++;
      if (pn <= maxPages) {
        await sleep(1500);
      }
    }
    return result;
  }

  static async unfavorite(aid: number, mediaIds: number[]): Promise<void> {
    const session: BiliSession = BiliSession.getInstance();
    if (!session.isLogged()) {
      throw new Error('请先登录B站账号');
    }
    if (session.biliJct === '') {
      throw new Error('缺少bili_jct，请重新登录');
    }
    for (let i = 0; i < mediaIds.length; i++) {
      const body: string =
        `rid=${aid}&type=2&add_media_ids=&del_media_ids=${mediaIds[i]}&csrf=${session.biliJct}`;
      const resultStr: string = await httpPostForm(BILI_FAV_DEAL_URL, body);
      parseApiData(resultStr);
    }
  }

  static async favorite(aid: number, mediaIds: number[]): Promise<void> {
    const session: BiliSession = BiliSession.getInstance();
    if (!session.isLogged()) {
      throw new Error('请先登录B站账号');
    }
    if (session.biliJct === '') {
      throw new Error('缺少bili_jct，请重新登录');
    }
    for (let i = 0; i < mediaIds.length; i++) {
      const body: string =
        `rid=${aid}&type=2&add_media_ids=${mediaIds[i]}&del_media_ids=&csrf=${session.biliJct}`;
      const resultStr: string = await httpPostForm(BILI_FAV_DEAL_URL, body);
      parseApiData(resultStr);
    }
  }

  static async ensureBuvid(): Promise<void> {
    const session: BiliSession = BiliSession.getInstance();
    if (session.hasBuvid()) {
      return;
    }
    for (let attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await sleep(800 * attempt);
      }
      try {
        const resultStr: string = await httpGet(BILI_SPI_URL);
        const data: Record<string, Object> = parseApiData(resultStr);
        if (data['b_3'] !== undefined) {
          session.buvid3 = data['b_3'] as string;
        }
        if (data['b_4'] !== undefined) {
          session.buvid4 = data['b_4'] as string;
        }
        if (session.hasBuvid()) {
          hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'buvid fetched');
          // US3：buvid 获取成功后执行一次 ExClimbWuzhi 激活（fire-and-forget，失败静默）
          BiliService.activateBuvid().catch((): void => {});
          return;
        }
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'buvid fetch failed: %{public}s', error.message);
      }
    }
  }

  // US3：buvid 激活状态（每进程仅激活一次；失败不重试，下次进程启动可再试）
  private static buvidActivated: boolean = false;

  // US3：ExClimbWuzhi 风控网关 buvid 激活（PiliPlus 最小伪装 payload）：
  // JSON body `{payload: <json串>}`，携带 buvid3 Cookie 与 BiliDroid UA；
  // 从响应 Set-Cookie 被动收集 b_nut 存入 BiliSession；全程失败静默不阻塞主流程
  static async activateBuvid(): Promise<void> {
    if (BiliService.buvidActivated) {
      return;
    }
    const session: BiliSession = BiliSession.getInstance();
    if (session.buvid3 === '') {
      return;
    }
    BiliService.buvidActivated = true;
    try {
      // payload 种子：32 随机字节 + 4 零字节 + 'IEND' + 4 随机字节，base64 后取末 50 字符
      const seed: Uint8Array = new Uint8Array(44);
      for (let i: number = 0; i < 32; i++) {
        seed[i] = Math.floor(Math.random() * 256);
      }
      seed[36] = 73; // 'I'
      seed[37] = 69; // 'E'
      seed[38] = 78; // 'N'
      seed[39] = 68; // 'D'
      for (let i: number = 40; i < 44; i++) {
        seed[i] = Math.floor(Math.random() * 256);
      }
      const b64: string = base64EncodeBytes(seed);
      const payload: string = b64.substring(b64.length - 50);
      const gaia3c43: Record<string, Object> = {
        'adca': 'Linux',
        'bfe9': payload,
      };
      const gaia: Record<string, Object> = {
        '3064': 1,
        '39c8': '333.1387.fp.risk',
        '3c43': gaia3c43,
      };
      const body: Record<string, Object> = { 'payload': JSON.stringify(gaia) };
      const setCookie: string =
        await BiliService.postExClimbWuzhi(JSON.stringify(body), session.buvid3);
      if (setCookie !== '') {
        session.collectSetCookie(setCookie);
      }
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'buvid activated');
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'buvid activate failed');
    }
  }

  // US3：ExClimbWuzhi POST（JSON body + buvid3 Cookie + BiliDroid UA）；
  // 不校验响应码/响应体（激活结果不敏感），仅收集 Set-Cookie 返回
  private static async postExClimbWuzhi(body: string, buvid3: string): Promise<string> {
    const httpRequest: http.HttpRequest = http.createHttp();
    const headers: Record<string, string> = {
      'User-Agent': Constants.BILI_APP_USER_AGENT,
      'Content-Type': 'application/json',
      'Cookie': `buvid3=${buvid3}`,
    };
    try {
      const response: http.HttpResponse = await httpRequest.request(Constants.BILI_EXCLIMB_WUZHI_URL, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        usingCache: false,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: Constants.CONNECT_TIMEOUT_MS,
        readTimeout: Constants.READ_TIMEOUT_MS,
      });
      Logger.log('net', logUrl(Constants.BILI_EXCLIMB_WUZHI_URL), `HTTP ${response.responseCode}`);
      let setCookie: string = '';
      const header: Record<string, Object> = response.header as Record<string, Object>;
      let sc: Object = header['set-cookie'];
      if (sc === undefined) {
        sc = header['Set-Cookie'];
      }
      if (typeof sc === 'string') {
        setCookie = sc;
      } else if (Array.isArray(sc)) {
        const arr: Object[] = sc as Object[];
        for (let i: number = 0; i < arr.length; i++) {
          const part: string = arr[i] as string;
          setCookie = setCookie === '' ? part : `${setCookie}\n${part}`;
        }
      }
      return setCookie;
    } finally {
      httpRequest.destroy();
    }
  }

  static async fetchQrLoginUrl(): Promise<QrLoginInfo> {
    const resultStr: string = await httpGet(BILI_QR_GENERATE_URL);
    const data: Record<string, Object> = parseApiData(resultStr);
    const info: QrLoginInfo = new QrLoginInfo();
    if (data['url'] !== undefined) {
      info.url = data['url'] as string;
    }
    if (data['qrcode_key'] !== undefined) {
      info.qrcodeKey = data['qrcode_key'] as string;
    }
    if (info.url === '' || info.qrcodeKey === '') {
      throw new Error('获取二维码失败');
    }
    return info;
  }

  static async pollQrLogin(qrcodeKey: string): Promise<QrPollResult> {
    const result: QrPollResult = new QrPollResult();
    const resp: QrPollHttpResult = await httpGetWithCookies(`${BILI_QR_POLL_URL}?qrcode_key=${qrcodeKey}`);
    const root: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
    const outerCode: number = root['code'] as number;
    const dataRaw: Object = root['data'];
    const data: Record<string, Object> =
      dataRaw === undefined || dataRaw === null ? {} : dataRaw as Record<string, Object>;
    const dataCodeRaw: Object = data['code'];
    const code: number = dataCodeRaw === undefined || dataCodeRaw === null ? outerCode : dataCodeRaw as number;
    const urlRaw: Object = data['url'];
    const url: string = urlRaw === undefined || urlRaw === null ? '' : urlRaw as string;
    if (code === 0) {
      let cookie: string = BiliService.cookieFromSetCookies(resp.setCookie);
      if (cookie === '') {
        cookie = BiliService.cookieFromCrossDomainUrl(url);
      }
      if (cookie === '') {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'qr login parse failed: urlLen=%{public}d, setCookieLen=%{public}d',
          url.length, resp.setCookie.length);
        throw new Error('解析登录信息失败');
      }
      result.status = QrPollStatus.SUCCESS;
      result.cookie = cookie;
      return result;
    }
    if (code === 86090) {
      result.status = QrPollStatus.SCANNED;
    } else if (code === 86038) {
      result.status = QrPollStatus.EXPIRED;
    } else {
      result.status = QrPollStatus.WAITING;
    }
    return result;
  }

  private static cookieFromSetCookies(setCookie: string): string {
    if (setCookie === '') {
      return '';
    }
    let sessdata: string = '';
    let biliJct: string = '';
    let dedeUserId: string = '';
    const segments: string[] = setCookie.split(';').join('\n').split(',').join('\n').split('\n');
    for (let i = 0; i < segments.length; i++) {
      const seg: string = segments[i].trim();
      if (seg.length === 0) {
        continue;
      }
      const eq: number = seg.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const name: string = seg.substring(0, eq).trim();
      const value: string = seg.substring(eq + 1).trim();
      if (name === 'SESSDATA' && sessdata === '') {
        sessdata = value;
      } else if (name === 'bili_jct' && biliJct === '') {
        biliJct = value;
      } else if (name === 'DedeUserID' && dedeUserId === '') {
        dedeUserId = value;
      }
    }
    if (sessdata === '' || biliJct === '') {
      return '';
    }
    let cookie: string = `SESSDATA=${sessdata}; bili_jct=${biliJct}`;
    if (dedeUserId !== '') {
      cookie = `${cookie}; DedeUserID=${dedeUserId}`;
    }
    return cookie;
  }

  private static cookieFromCrossDomainUrl(url: string): string {
    const queryStart: number = url.indexOf('?');
    if (queryStart < 0) {
      return '';
    }
    const query: string = url.substring(queryStart + 1);
    const parts: string[] = query.split('&');
    let sessdata: string = '';
    let biliJct: string = '';
    let dedeUserId: string = '';
    for (let i = 0; i < parts.length; i++) {
      const kv: string[] = parts[i].split('=');
      if (kv.length < 2) {
        continue;
      }
      const key: string = kv[0];
      const value: string = kv.slice(1).join('=');
      if (key === 'SESSDATA') {
        sessdata = value;
      } else if (key === 'bili_jct') {
        biliJct = value;
      } else if (key === 'DedeUserID') {
        dedeUserId = value;
      }
    }
    if (sessdata === '' || biliJct === '') {
      return '';
    }
    let cookie: string = `SESSDATA=${sessdata}; bili_jct=${biliJct}`;
    if (dedeUserId !== '') {
      cookie = `${cookie}; DedeUserID=${dedeUserId}`;
    }
    return cookie;
  }

  static async fetchVideoInfo(bvid: string): Promise<BiliVideo> {
    const resultStr: string = await httpGet(`${BILI_VIDEO_INFO_URL}?bvid=${bvid}`);
    const data: Record<string, Object> = parseApiData(resultStr);
    const video: BiliVideo = BiliVideo.create(
      data['bvid'] as string,
      data['aid'] as number,
      data['cid'] as number,
      data['title'] as string,
      data['pic'] as string,
      data['duration'] as number,
    );
    const ownerRaw: Object = data['owner'];
    if (ownerRaw !== undefined && ownerRaw !== null) {
      const owner: Record<string, Object> = ownerRaw as Record<string, Object>;
      if (owner['mid'] !== undefined) {
        video.ownerMid = owner['mid'] as number;
      }
      if (owner['name'] !== undefined) {
        video.ownerName = owner['name'] as string;
      }
      if (owner['face'] !== undefined) {
        video.ownerFace = owner['face'] as string;
      }
    }
    if (data['desc'] !== undefined && data['desc'] !== null) {
      video.desc = data['desc'] as string;
    }
    if (data['pubdate'] !== undefined && data['pubdate'] !== null) {
      video.pubdate = data['pubdate'] as number;
    }
    const statRaw: Object = data['stat'];
    if (statRaw !== undefined && statRaw !== null) {
      const stat: Record<string, Object> = statRaw as Record<string, Object>;
      if (stat['view'] !== undefined && stat['view'] !== null) {
        video.view = stat['view'] as number;
      }
    }
    return video;
  }

  static async fetchDashAudioCandidates(bvid: string, cid: number, preferLowBitrate: boolean = false): Promise<string[]> {
    const resultStr: string = await httpGet(
      `${BILI_PLAY_URL_API}?bvid=${bvid}&cid=${cid}&qn=16&fnver=0&fnval=16&fourk=0`
    );
    const data: Record<string, Object> = parseApiData(resultStr);
    if (data['dash'] === undefined) {
      throw new Error('No dash data');
    }
    const dash: Record<string, Object> = data['dash'] as Record<string, Object>;
    const audioArr: Object[] = dash['audio'] as Object[];
    if (audioArr.length === 0) {
      throw new Error('No audio stream found');
    }
    let best: Record<string, Object> = audioArr[0] as Record<string, Object>;
    let bestBandwidth: number = best['bandwidth'] as number;
    for (let i = 1; i < audioArr.length; i++) {
      const item: Record<string, Object> = audioArr[i] as Record<string, Object>;
      const bw: number = item['bandwidth'] as number;
      if (preferLowBitrate) {
        if (bw < bestBandwidth) {
          bestBandwidth = bw;
          best = item;
        }
      } else {
        if (bw > bestBandwidth) {
          bestBandwidth = bw;
          best = item;
        }
      }
    }
    const candidates: string[] = [];
    if (best['baseUrl'] !== undefined) {
      const baseUrl: string = best['baseUrl'] as string;
      if (baseUrl !== '') {
        candidates.push(baseUrl);
      }
    }
    if (best['backupUrl'] !== undefined) {
      const backup: Object[] = best['backupUrl'] as Object[];
      for (let i = 0; i < backup.length; i++) {
        const u: string = backup[i] as string;
        if (u !== '' && candidates.indexOf(u) < 0) {
          candidates.push(u);
        }
      }
    }
    const stable: string[] = candidates.filter((u: string) => u.indexOf('mcdn') < 0);
    if (stable.length > 0) {
      return stable;
    }
    if (candidates.length === 0) {
      throw new Error('No audio URL found');
    }
    return candidates;
  }

  static async fetchDurlCandidates(bvid: string, cid: number): Promise<string[]> {
    const resultStr: string = await httpGet(
      `${BILI_PLAY_URL_API}?bvid=${bvid}&cid=${cid}&qn=16&fnver=0&fnval=0&fourk=0`
    );
    const data: Record<string, Object> = parseApiData(resultStr);
    if (data['durl'] === undefined) {
      throw new Error('No durl data');
    }
    const durl: Object[] = data['durl'] as Object[];
    if (durl.length === 0) {
      throw new Error('No direct URL found');
    }
    const first: Record<string, Object> = durl[0] as Record<string, Object>;
    const candidates: string[] = [];
    if (first['url'] !== undefined) {
      const url: string = first['url'] as string;
      if (url !== '') {
        candidates.push(url);
      }
    }
    if (first['backup_url'] !== undefined) {
      const backup: Object[] = first['backup_url'] as Object[];
      for (let i = 0; i < backup.length; i++) {
        const u: string = backup[i] as string;
        if (u !== '' && candidates.indexOf(u) < 0) {
          candidates.push(u);
        }
      }
    }
    if (candidates.length === 0) {
      throw new Error('No direct URL found');
    }
    return candidates;
  }

  // 流式直链解析（US2）：取视频 cid 后走 dash 音轨直链（mcdn 过滤），失败降级 durl；
  // 不做任何下载，直链由播放器带 Referer/UA 请求头边下边播
  static async resolveAudioUrl(bvid: string, preferLowBitrate: boolean = false): Promise<string[]> {
    const video: BiliVideo = await BiliService.fetchVideoInfo(bvid);
    return BiliService.resolveAudioUrlFromCid(bvid, video.cid, preferLowBitrate);
  }

  // resolveAudioUrl 的核心：调用方已持有 cid（如 playIndex 元数据刷新已拉过视频信息）时避免重复请求
  static async resolveAudioUrlFromCid(bvid: string, cid: number, preferLowBitrate: boolean = false): Promise<string[]> {
    try {
      return await BiliService.fetchDashAudioCandidates(bvid, cid, preferLowBitrate);
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'dash audio failed, fallback to durl: %{public}s', bvid);
      return await BiliService.fetchDurlCandidates(bvid, cid);
    }
  }

  // 缓存优先（US2）：本地已有完整可用的缓存文件（dash 下载期的 .m4a / durl 兜底的 .mp4）则返回路径，否则空串
  static cachedAudioPath(bvid: string): string {
    try {
      const context = getContext() as common.UIAbilityContext;
      const names: string[] = [`${bvid}.m4a`, `${bvid}.mp4`];
      for (let i = 0; i < names.length; i++) {
        const path: string = `${context.cacheDir}/${names[i]}`;
        if (fs.accessSync(path) && isValidMediaFile(path)) {
          hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'stream: reuse cached file: %{public}s', path);
          return path;
        }
      }
    } catch (e) {}
    return '';
  }

  static cacheSizeMB(): number {
    try {
      const context = getContext() as common.UIAbilityContext;
      const names: string[] = fs.listFileSync(context.cacheDir);
      let total: number = 0;
      for (let i = 0; i < names.length; i++) {
        if (!isMediaCacheName(names[i])) {
          continue;
        }
        try {
          const stat: fs.Stat = fs.statSync(`${context.cacheDir}/${names[i]}`);
          total += stat.size;
        } catch (e) {}
      }
      return total / Constants.BYTES_PER_MB;
    } catch (e) {
      return 0;
    }
  }

  static clearAllCache(): void {
    try {
      const context = getContext() as common.UIAbilityContext;
      const names: string[] = fs.listFileSync(context.cacheDir);
      for (let i = 0; i < names.length; i++) {
        if (!isMediaCacheName(names[i])) {
          continue;
        }
        try { fs.unlinkSync(`${context.cacheDir}/${names[i]}`); } catch (e) {}
      }
    } catch (e) {}
  }

  static cleanCache(keepPath: string): void {
    try {
      const context = getContext() as common.UIAbilityContext;
      const names: string[] = fs.listFileSync(context.cacheDir);
      const entries: CacheEntry[] = [];
      let totalSize: number = 0;
      for (let i = 0; i < names.length; i++) {
        if (!isMediaCacheName(names[i])) {
          continue;
        }
        try {
          const path: string = `${context.cacheDir}/${names[i]}`;
          const stat: fs.Stat = fs.statSync(path);
          const entry: CacheEntry = new CacheEntry();
          entry.name = names[i];
          entry.mtimeMs = stat.mtime;
          entry.size = stat.size;
          entries.push(entry);
          totalSize += stat.size;
        } catch (e) {}
      }
      if (totalSize < Constants.MAX_CACHE_BYTES) {
        return;
      }
      entries.sort((a: CacheEntry, b: CacheEntry): number => a.mtimeMs - b.mtimeMs);
      for (let i = 0; i < entries.length; i++) {
        if (totalSize < Constants.TARGET_CACHE_BYTES) {
          break;
        }
        const path: string = `${context.cacheDir}/${entries[i].name}`;
        if (path === keepPath) {
          continue;
        }
        try {
          fs.unlinkSync(path);
          totalSize -= entries[i].size;
        } catch (e) {}
      }
    } catch (e) {}
  }
}
