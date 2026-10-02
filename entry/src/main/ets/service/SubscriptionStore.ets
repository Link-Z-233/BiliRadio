import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BiliVideo } from '../model/BiliVideo';
import { Subscription } from '../model/Subscription';
import { BiliService, FolderFetchResult } from './BiliService';
import { Constants, sleep } from './Constants';
import { FileUtil } from './FileUtil';

const SUBSCRIPTIONS_FILE: string = 'subscriptions.json';
const SUB_CACHE_PREFIX: string = 'sub_cache_';

export type SubRefreshCallback = (sub: Subscription, ok: boolean) => void;

// 订阅数据唯一存取点：subscriptions.json（订阅列表）+ sub_cache_<id>.json（各源剧集缓存）
export class SubscriptionStore {

  static loadSubscriptions(): Subscription[] {
    const list: Subscription[] = [];
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/${SUBSCRIPTIONS_FILE}`;
      if (!fs.accessSync(path)) {
        return list;
      }
      const content: string = FileUtil.readTextFile(path);
      if (content === '') {
        return list;
      }
      const root: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      if (root['items'] !== undefined) {
        const records: Object[] = root['items'] as Object[];
        for (let i = 0; i < records.length; i++) {
          const sub: Subscription = Subscription.fromRecord(records[i] as Record<string, Object>);
          if (sub.id === '' || sub.type === '') {
            continue;
          }
          list.push(sub);
        }
      }
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'loadSubscriptions failed');
    }
    return list;
  }

  static saveSubscriptions(list: Subscription[]): void {
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/${SUBSCRIPTIONS_FILE}`;
      const records: Array<Record<string, Object>> = [];
      for (let i = 0; i < list.length; i++) {
        records.push(list[i].toRecord());
      }
      const rec: Record<string, Object> = {
        'items': records,
      };
      FileUtil.writeTextFile(path, JSON.stringify(rec));
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'saveSubscriptions failed');
    }
  }

  static loadEpisodes(id: string): BiliVideo[] {
    const items: BiliVideo[] = [];
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/${SubscriptionStore.cacheFileName(id)}`;
      if (!fs.accessSync(path)) {
        return items;
      }
      const content: string = FileUtil.readTextFile(path);
      if (content === '') {
        return items;
      }
      const root: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      if (root['items'] !== undefined) {
        const records: Object[] = root['items'] as Object[];
        for (let i = 0; i < records.length; i++) {
          const item: BiliVideo = BiliVideo.fromRecord(records[i] as Record<string, Object>);
          if (item.bvid === '') {
            continue;
          }
          items.push(item);
        }
      }
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'loadEpisodes failed: %{public}s', id);
    }
    return items;
  }

  static saveEpisodes(id: string, items: BiliVideo[]): void {
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/${SubscriptionStore.cacheFileName(id)}`;
      const records: Array<Record<string, Object>> = [];
      for (let i = 0; i < items.length; i++) {
        records.push(items[i].toRecord());
      }
      const rec: Record<string, Object> = {
        'items': records,
      };
      FileUtil.writeTextFile(path, JSON.stringify(rec));
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'saveEpisodes failed: %{public}s', id);
    }
  }

  static removeEpisodes(id: string): void {
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/${SubscriptionStore.cacheFileName(id)}`;
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'removeEpisodes failed: %{public}s', id);
    }
  }

  // id 形如 'up:546195'，冒号不能出现在文件名中
  private static cacheFileName(id: string): string {
    return `${SUB_CACHE_PREFIX}${id.split(':').join('_')}.json`;
  }

  // 刷新单个订阅：按类型分发拉取，统一存为新集在前，并更新刷新时间与最新发布时间
  // ponytail: 契约——四类源统一「近期一页」语义（up=30/fav=20/season=20/series=30），
  // saveEpisodes 整体覆盖写，sub_cache 只存近期条目；单集播放按需 fetchVideoInfo+取流；
  // 超过页大小的新集会少计（播客语义可接受）；SourcePage 滚动追加更老条目时只进内存不写缓存
  static async refreshSubscription(sub: Subscription): Promise<BiliVideo[]> {
    let items: BiliVideo[] = [];
    if (sub.type === Subscription.TYPE_UP) {
      items = await BiliService.fetchUpVideos(sub.sourceId);
    } else if (sub.type === Subscription.TYPE_FAV) {
      // 只取最新一页（20 条）：播客「近期节目」语义，超大收藏夹不做全量刷新
      const result: FolderFetchResult = await BiliService.fetchFolderVideos(sub.sourceId, 0, undefined, 1);
      items = result.items;
    } else if (sub.type === Subscription.TYPE_SEASON) {
      // 倒序取最新一页；sort_reverse=true 行为需冒烟确认，若不被支持回退末页策略
      items = await BiliService.fetchSeasonVideos(sub.ownerMid, sub.sourceId, 1, true);
    } else if (sub.type === Subscription.TYPE_SERIES) {
      items = await BiliService.fetchSeriesVideos(sub.ownerMid, sub.sourceId, 1, true);
    } else {
      throw new Error(`未知订阅类型: ${sub.type}`);
    }
    items.sort((a: BiliVideo, b: BiliVideo): number => b.pubdate - a.pubdate);
    sub.lastRefreshAt = Date.now();
    if (items.length > 0 && items[0].pubdate > 0) {
      sub.latestPubAt = items[0].pubdate;
    }
    // 收藏夹/合集列表接口不返回封面与 UP 名，用最新一集回填
    if (sub.cover === '' && items.length > 0 && items[0].cover !== '') {
      sub.cover = items[0].cover;
    }
    if (sub.upperName === '' && items.length > 0 && items[0].ownerName !== '') {
      sub.upperName = items[0].ownerName;
    }
    SubscriptionStore.saveEpisodes(sub.id, items);
    return items;
  }

  // 串行逐源刷新：单源失败不阻塞其余源；force=false 时跳过 TTL 内已刷新的源
  static async refreshAll(list: Subscription[], force: boolean,
    onOneDone: SubRefreshCallback | undefined): Promise<void> {
    for (let i = 0; i < list.length; i++) {
      const sub: Subscription = list[i];
      if (!force && Subscription.isCacheFresh(sub.lastRefreshAt, Date.now())) {
        continue;
      }
      let ok: boolean = true;
      try {
        await SubscriptionStore.refreshSubscription(sub);
      } catch (e) {
        ok = false;
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'refresh sub failed: %{public}s', sub.id);
      }
      if (onOneDone !== undefined) {
        onOneDone(sub, ok);
      }
      await sleep(800);
    }
  }
}
