import { BiliVideo } from './BiliVideo';

// 播放历史条目（play-history-progress）：字段/单位对齐 B 站历史接口格式——
// progress/duration 以秒为单位（progress=-1 表示已看完，对齐 B 站语义），viewAt 为秒级时间戳，cid 为分P标识。
// 旧格式（playedAt 毫秒）由 fromRecord 迁移：viewAt 缺失且 playedAt 存在 → floor(playedAt/1000)，无回滚兼容义务。
export class PlayHistoryItem {
  // 来源类别：0=个人收藏夹 / 1=UP主合集 / 2=本地内容
  static readonly SOURCE_FAVORITE: number = 0;
  static readonly SOURCE_SEASON: number = 1;
  static readonly SOURCE_LOCAL: number = 2;

  bvid: string = '';
  title: string = '';
  ownerName: string = '';
  sourceType: number = PlayHistoryItem.SOURCE_FAVORITE;
  // 秒级时间戳（最后播放时间，对齐 B 站 view_at）；任何写入点禁止传入毫秒
  viewAt: number = 0;
  cover: string = '';
  // 播放进度（秒）：-1 = 已看完（仅由完播判定写入）；0 = 未记录进度
  progress: number = 0;
  // 总时长（秒）：0 = 未知（prepared 后由播放器真实时长回填）
  duration: number = 0;
  // 分P标识：0 = 未知（流式路径取 currentCid 回填）
  cid: number = 0;

  // playedAtMs 为毫秒时间戳（调用方传 Date.now()），内部转秒存入 viewAt
  static fromVideo(video: BiliVideo, sourceType: number, playedAtMs: number): PlayHistoryItem {
    const r = new PlayHistoryItem();
    r.bvid = video.bvid;
    r.title = video.title;
    r.ownerName = video.ownerName;
    r.sourceType = sourceType;
    r.viewAt = Math.floor(playedAtMs / 1000);
    r.cover = video.cover;
    // cid/duration 冷启动兜底（plan R7）：BiliVideo.cid 与 duration 均已是秒/直通单位
    r.cid = video.cid;
    r.duration = video.duration;
    return r;
  }

  toRecord(): Record<string, Object> {
    const rec: Record<string, Object> = {
      'bvid': this.bvid,
      'title': this.title,
      'ownerName': this.ownerName,
      'sourceType': this.sourceType,
      'viewAt': this.viewAt,
      'cover': this.cover,
      'progress': this.progress,
      'duration': this.duration,
      'cid': this.cid,
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
    if (rec['viewAt'] !== undefined) {
      r.viewAt = rec['viewAt'] as number;
    } else if (rec['playedAt'] !== undefined) {
      // 旧格式迁移（plan R2）：viewAt 缺失且旧 playedAt（毫秒）存在 → 秒
      r.viewAt = Math.floor((rec['playedAt'] as number) / 1000);
    }
    if (rec['cover'] !== undefined) {
      r.cover = rec['cover'] as string;
    }
    if (rec['progress'] !== undefined) {
      r.progress = rec['progress'] as number;
    }
    if (rec['duration'] !== undefined) {
      r.duration = rec['duration'] as number;
    }
    if (rec['cid'] !== undefined) {
      r.cid = rec['cid'] as number;
    }
    return r;
  }
}
