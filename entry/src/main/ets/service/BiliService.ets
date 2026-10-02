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
const BILI_SPACE_ACC_INFO_URL: string = 'https://api.bilibili.com/x/space/wbi/acc/info';
const BILI_QR_GENERATE_URL: string = 'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';
const BILI_QR_POLL_URL: string = 'https://passport.bilibili.com/x/passport-login/web/qrcode/poll';
const REFERER: string = 'https://www.bilibili.com';
const USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
// 空间接口风控三件套：PC Safari UA + space Referer/Origin（接口参数为公开事实性配置）
const SPACE_ORIGIN: string = 'https://space.bilibili.com';
const SPACE_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15';


export type DownloadProgressCallback = (receivedBytes: number, totalBytes: number) => void;
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

// 风控指纹占位：dm_img_str/dm_cover_img_str 用随机 base64（固定假值实测 -403）
function randomDmImgStr(): string {
  const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let s: string = '';
  for (let i = 0; i < 96; i++) {
    s += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return s;
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

function checkJsonBody(url: string, result: string): string {
  const trimmed: string = result.trim();
  if (trimmed === '') {
    throw new Error(`接口返回空响应: ${url.substring(0, 60)}`);
  }
  if (trimmed.charAt(0) !== '{' && trimmed.charAt(0) !== '[') {
    hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'non-json body: %{public}s', url.substring(0, 80));
    throw new Error('接口返回异常(疑似B站风控)，请稍后再试');
  }
  return trimmed;
}

function httpGet(url: string, headers: Record<string, string> | undefined = undefined): Promise<string> {
  const httpRequest: http.HttpRequest = http.createHttp();
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
    if (code !== 200) {
      throw new Error(`HTTP ${code}`);
    }
    return checkJsonBody(url, result);
  }).catch((err: BusinessError) => {
    httpRequest.destroy();
    throw new Error(`HTTP request failed: ${err.message}`);
  });
}

function httpGetWithCookies(url: string): Promise<QrPollHttpResult> {
  const httpRequest: http.HttpRequest = http.createHttp();
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
    if (code !== 200) {
      throw new Error(`HTTP ${code}`);
    }
    const out: QrPollHttpResult = new QrPollHttpResult();
    out.body = checkJsonBody(url, result);
    out.setCookie = setCookie;
    return out;
  }).catch((err: BusinessError) => {
    httpRequest.destroy();
    throw new Error(`HTTP request failed: ${err.message}`);
  });
}

function httpPostForm(url: string, body: string): Promise<string> {
  const httpRequest: http.HttpRequest = http.createHttp();
  const headers: Record<string, string> = buildHeaders();
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
    if (code !== 200) {
      throw new Error(`HTTP ${code}`);
    }
    return checkJsonBody(url, result);
  }).catch((err: BusinessError) => {
    httpRequest.destroy();
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
          }
          if (seasonId === 0) {
            continue;
          }
          seasons.push(new Season(seasonId, title, count));
        }
      }
    }
    return seasons;
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

  // UP 主最新投稿（单页 30 条，新集在前）
  // ponytail: 只取第一页——播客「近期节目」语义；升级路径：SourcePage 滚动到底按需追加页
  static async fetchUpVideos(mid: number): Promise<BiliVideo[]> {
    const mixinKey: string = await BiliService.fetchMixinKey();
    const params: Record<string, string> = {
      'mid': mid.toString(),
      'ps': '30',
      'pn': '1',
      'order': 'pubdate',
      'platform': 'web',
      'dm_img_str': randomDmImgStr(),
      'dm_cover_img_str': randomDmImgStr(),
    };
    const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
    const resultStr: string = await httpGet(`${BILI_SPACE_ARC_SEARCH_URL}?${signedQuery}`, buildSpaceHeaders(mid));
    const data: Record<string, Object> = parseApiData(resultStr);
    const items: BiliVideo[] = [];
    const listRaw: Object = data['list'];
    if (listRaw !== undefined && listRaw !== null) {
      const list: Record<string, Object> = listRaw as Record<string, Object>;
      const vlistRaw: Object = list['vlist'];
      if (vlistRaw !== undefined && vlistRaw !== null) {
        const arr: Object[] = vlistRaw as Object[];
        for (let i = 0; i < arr.length; i++) {
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

  static async fetchUpInfo(mid: number): Promise<UpInfo> {
    const mixinKey: string = await BiliService.fetchMixinKey();
    const params: Record<string, string> = {
      'mid': mid.toString(),
    };
    const signedQuery: string = await WbiSigner.signParams(params, mixinKey);
    const resultStr: string = await httpGet(`${BILI_SPACE_ACC_INFO_URL}?${signedQuery}`, buildSpaceHeaders(mid));
    const data: Record<string, Object> = parseApiData(resultStr);
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
          return;
        }
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'buvid fetch failed: %{public}s', error.message);
      }
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

  static async downloadToFile(remoteUrl: string, destPath: string,
    onProgress: DownloadProgressCallback | undefined): Promise<string> {
    const localPath: string = destPath;

    if (fs.accessSync(localPath)) {
      if (isValidMediaFile(localPath)) {
        hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'reuse cached file: %{public}s', localPath);
        return localPath;
      }
      try { fs.unlinkSync(localPath); } catch (e) {}
    }

    const httpRequest: http.HttpRequest = http.createHttp();
    const file: fs.File = fs.openSync(localPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let totalBytes: number = -1;
    let receivedBytes: number = 0;
    let dataEnded: boolean = false;
    try {
      httpRequest.on('headersReceive', (header: Object) => {
        try {
          const rec: Record<string, Object> = header as Record<string, Object>;
          let lenValue: Object | undefined = rec['content-length'];
          if (lenValue === undefined) {
            lenValue = rec['Content-Length'];
          }
          if (lenValue !== undefined) {
            const n: number = Number(lenValue);
            if (!Number.isNaN(n) && n > 0) {
              totalBytes = n;
            }
          }
        } catch (e) {}
      });
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        fs.writeSync(file.fd, data);
        receivedBytes += data.byteLength;
        if (onProgress !== undefined) {
          onProgress(receivedBytes, totalBytes);
        }
      });
      httpRequest.on('dataEnd', () => {
        dataEnded = true;
      });

      const responseCode: number = await httpRequest.requestInStream(remoteUrl, {
        method: http.RequestMethod.GET,
        header: {
          'Referer': REFERER,
          'User-Agent': USER_AGENT,
        },
        usingCache: false,
        connectTimeout: Constants.CONNECT_TIMEOUT_MS,
        readTimeout: Constants.STREAM_TIMEOUT_MS,
      });
      if (responseCode !== 200) {
        throw new Error(`Download HTTP ${responseCode}`);
      }
      const deadline: number = Date.now() + 10000;
      while (!dataEnded) {
        if (Date.now() > deadline) {
          throw new Error('Download data timeout');
        }
        await sleep(20);
      }
      if (!isValidMediaFile(localPath)) {
        throw new Error('Downloaded file is not valid media');
      }
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'downloaded %{public}s, size=%{public}d', localPath, receivedBytes);
      return localPath;
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'download failed: %{public}s', error.message);
      try { fs.unlinkSync(localPath); } catch (e) {}
      throw new Error(`Download failed: ${error.message}`);
    } finally {
      try { fs.closeSync(file); } catch (e) {}
      try {
        httpRequest.off('headersReceive');
        httpRequest.off('dataReceive');
        httpRequest.off('dataEnd');
      } catch (e) {}
      httpRequest.destroy();
    }
  }

  static async downloadToCache(remoteUrl: string, fileName: string,
    onProgress: DownloadProgressCallback | undefined): Promise<string> {
    const context = getContext() as common.UIAbilityContext;
    const localPath: string = `${context.cacheDir}/${fileName}`;
    return BiliService.downloadToFile(remoteUrl, localPath, onProgress);
  }

  static async downloadFirstSuccessToFile(candidates: string[], destPath: string,
    onProgress: DownloadProgressCallback | undefined): Promise<string> {
    let lastError: Error = new Error('No download candidate');
    for (let i = 0; i < candidates.length; i++) {
      try {
        return await BiliService.downloadToFile(candidates[i], destPath, onProgress);
      } catch (err) {
        const error = err as BusinessError;
        lastError = new Error(error.message);
      }
    }
    throw lastError;
  }

  static async downloadFirstSuccess(candidates: string[], fileName: string,
    onProgress: DownloadProgressCallback | undefined): Promise<string> {
    let lastError: Error = new Error('No download candidate');
    for (let i = 0; i < candidates.length; i++) {
      try {
        hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'try download candidate %{public}d/%{public}d', i + 1, candidates.length);
        return await BiliService.downloadToCache(candidates[i], fileName, onProgress);
      } catch (err) {
        const error = err as BusinessError;
        lastError = new Error(error.message);
      }
    }
    throw lastError;
  }

  static async resolveAndDownload(bvid: string, onProgress?: DownloadProgressCallback, preferLowBitrate: boolean = false): Promise<BiliVideo> {
    const video: BiliVideo = await BiliService.fetchVideoInfo(bvid);

    let localPath: string = '';
    try {
      const audioCandidates: string[] = await BiliService.fetchDashAudioCandidates(video.bvid, video.cid, preferLowBitrate);
      localPath = await BiliService.downloadFirstSuccess(audioCandidates, `${bvid}.m4a`, onProgress);
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'dash audio failed, fallback to durl mp4');
      const durlCandidates: string[] = await BiliService.fetchDurlCandidates(video.bvid, video.cid);
      localPath = await BiliService.downloadFirstSuccess(durlCandidates, `${bvid}.mp4`, onProgress);
    }

    video.audioUrl = localPath;
    return video;
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
