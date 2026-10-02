import { BiliVideo } from './BiliVideo';

export class PlayHistoryItem {
  // 来源类别：0=个人收藏夹 / 1=UP主合集 / 2=本地内容
  static readonly SOURCE_FAVORITE: number = 0;
  static readonly SOURCE_SEASON: number = 1;
  static readonly SOURCE_LOCAL: number = 2;

  bvid: string = '';
  title: string = '';
  ownerName: string = '';
  sourceType: number = PlayHistoryItem.SOURCE_FAVORITE;
  playedAt: number = 0;
  cover: string = '';

  static fromVideo(video: BiliVideo, sourceType: number, playedAt: number): PlayHistoryItem {
    const r = new PlayHistoryItem();
    r.bvid = video.bvid;
    r.title = video.title;
    r.ownerName = video.ownerName;
    r.sourceType = sourceType;
    r.playedAt = playedAt;
    r.cover = video.cover;
    return r;
  }

  toRecord(): Record<string, Object> {
    const rec: Record<string, Object> = {
      'bvid': this.bvid,
      'title': this.title,
      'ownerName': this.ownerName,
      'sourceType': this.sourceType,
      'playedAt': this.playedAt,
      'cover': this.cover,
    };
    return rec;
  }

  static fromRecord(rec: Record<string, Object>): PlayHistoryItem {
    const r = new PlayHistoryItem();
    if (rec['bvid'] !== undefined) {
      r.bvid = rec['bvid'] as string;
    }
    if (rec['title'] !== undefined) {
      r.title = rec['title'] as string;
    }
    if (rec['ownerName'] !== undefined) {
      r.ownerName = rec['ownerName'] as string;
    }
    if (rec['sourceType'] !== undefined) {
      r.sourceType = rec['sourceType'] as number;
    }
    if (rec['playedAt'] !== undefined) {
      r.playedAt = rec['playedAt'] as number;
    }
    if (rec['cover'] !== undefined) {
      r.cover = rec['cover'] as string;
    }
    return r;
  }
}