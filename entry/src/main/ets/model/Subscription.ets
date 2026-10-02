import { BiliVideo } from './BiliVideo';

// 订阅源模型：四类源统一为「定期拉取剧集列表」的播客频道
export class Subscription {
  static readonly TYPE_UP: string = 'up';
  static readonly TYPE_FAV: string = 'fav';
  static readonly TYPE_SEASON: string = 'season';
  static readonly TYPE_SERIES: string = 'series';

  // ponytail: 全源统一 15min TTL（天花板；升级路径——按源类型/失败次数动态调整）
  static readonly CACHE_TTL_MS: number = 15 * 60 * 1000;

  id: string = '';            // `${type}:${sourceId}` 复合键
  type: string = '';          // TYPE_* 之一
  sourceId: number = 0;       // up:mid / fav:mediaId / season:seasonId / series:seriesId
  ownerMid: number = 0;       // season/series 拉取所需的所属 UP mid
  title: string = '';
  cover: string = '';
  upperName: string = '';
  lastSeenAt: number = 0;     // 秒；上次进入源详情时间，新集计数基准
  lastRefreshAt: number = 0;  // 毫秒；上次成功刷新时间，TTL 基准
  latestPubAt: number = 0;    // 秒；最新一集发布时间
  sortOrder: number = 0;

  static makeId(type: string, sourceId: number): string {
    return `${type}:${sourceId}`;
  }

  // 新集计数：pubdate 晚于 lastSeenAt 的剧集数（纯函数，可独立运行验证）
  // lastSeenAt=0 表示从未进入过源详情，全部视为旧内容，不显示 NEW
  static countNew(items: BiliVideo[], lastSeenAt: number): number {
    if (lastSeenAt === 0) {
      return 0;
    }
    let count: number = 0;
    for (let i = 0; i < items.length; i++) {
      if (items[i].pubdate > lastSeenAt) {
        count++;
      }
    }
    return count;
  }

  // 缓存新鲜度判定（纯函数，可独立运行验证）
  static isCacheFresh(lastRefreshAt: number, now: number): boolean {
    return lastRefreshAt > 0 && now - lastRefreshAt < Subscription.CACHE_TTL_MS;
  }

  toRecord(): Record<string, Object> {
    const rec: Record<string, Object> = {
      'id': this.id,
      'type': this.type,
      'sourceId': this.sourceId,
      'ownerMid': this.ownerMid,
      'title': this.title,
      'cover': this.cover,
      'upperName': this.upperName,
      'lastSeenAt': this.lastSeenAt,
      'lastRefreshAt': this.lastRefreshAt,
      'latestPubAt': this.latestPubAt,
      'sortOrder': this.sortOrder,
    };
    return rec;
  }

  static fromRecord(rec: Record<string, Object>): Subscription {
    const s = new Subscription();
    if (rec['id'] !== undefined) {
      s.id = rec['id'] as string;
    }
    if (rec['type'] !== undefined) {
      s.type = rec['type'] as string;
    }
    if (rec['sourceId'] !== undefined) {
      s.sourceId = rec['sourceId'] as number;
    }
    if (rec['ownerMid'] !== undefined) {
      s.ownerMid = rec['ownerMid'] as number;
    }
    if (rec['title'] !== undefined) {
      s.title = rec['title'] as string;
    }
    if (rec['cover'] !== undefined) {
      s.cover = rec['cover'] as string;
    }
    if (rec['upperName'] !== undefined) {
      s.upperName = rec['upperName'] as string;
    }
    if (rec['lastSeenAt'] !== undefined) {
      s.lastSeenAt = rec['lastSeenAt'] as number;
    }
    if (rec['lastRefreshAt'] !== undefined) {
      s.lastRefreshAt = rec['lastRefreshAt'] as number;
    }
    if (rec['latestPubAt'] !== undefined) {
      s.latestPubAt = rec['latestPubAt'] as number;
    }
    if (rec['sortOrder'] !== undefined) {
      s.sortOrder = rec['sortOrder'] as number;
    }
    return s;
  }
}
