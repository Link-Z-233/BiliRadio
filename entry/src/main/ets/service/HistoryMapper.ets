import { PlayHistoryItem } from '../model/PlayHistoryItem';

// 同步预留边界（play-history-progress FR-011/FR-012）：本地播放历史条目 ↔ B 站历史接口条目格式的
// 集中映射层。本地字段命名与单位已在 PlayHistoryItem 侧对齐 B 站（progress/duration 秒、viewAt 秒级
// 时间戳、-1=看完），本层只做字段一一对应 + 少量占位填充的纯静态映射，无 IO、无状态。
// 本轮无网络调用方（FR-012：不发起任何 B 站历史同步请求）；fromBiliHistory 供未来登录态下的
// 历史拉取合并使用，toBiliHistory 供未来心跳上报使用。

// B 站历史接口条目格式的本地镜像（字段对照参照 PiliPlus HistoryItemModel/History）：
// business 固定 'archive'（UGC 视频）；showTitle 对应 show_title（分P名），本地无此数据，结构占位
export class BiliHistoryRecord {
  bvid: string = '';          // history.bvid / 项级 bvid：UGC 视频标识
  cid: number = 0;            // history.cid：分P标识
  progress: number = 0;       // progress：秒；-1 = 看完（单位/语义已对齐，映射直通）
  duration: number = 0;       // duration：秒
  viewAt: number = 0;         // view_at：秒级时间戳
  title: string = '';         // title：标题
  showTitle: string = '';     // show_title：分P名（本地无此数据，映射时置空）
  authorName: string = '';    // author_name：UP 主名
  cover: string = '';         // cover：封面
  business: string = 'archive'; // history.business：UGC 视频固定 'archive'
}

export class HistoryMapper {
  // 本地条目 → B 站历史条目格式：单位直通（秒/秒/秒级时间戳），showTitle 置空、business='archive'
  static toBiliHistory(item: PlayHistoryItem): BiliHistoryRecord {
    const rec = new BiliHistoryRecord();
    rec.bvid = item.bvid;
    rec.cid = item.cid;
    rec.progress = item.progress;
    rec.duration = item.duration;
    rec.viewAt = item.viewAt;
    rec.title = item.title;
    rec.showTitle = '';
    rec.authorName = item.ownerName;
    rec.cover = item.cover;
    rec.business = 'archive';
    return rec;
  }

  // B 站历史条目 → 本地条目：sourceType 置 SOURCE_LOCAL（云端拉取条目无本地收藏夹/合集归属），
  // 进度语义原样保留（含 -1）；本轮无调用方，为未来拉取合并预留
  static fromBiliHistory(rec: BiliHistoryRecord): PlayHistoryItem {
    const item = new PlayHistoryItem();
    item.bvid = rec.bvid;
    item.cid = rec.cid;
    item.progress = rec.progress;
    item.duration = rec.duration;
    item.viewAt = rec.viewAt;
    item.title = rec.title;
    item.ownerName = rec.authorName;
    item.cover = rec.cover;
    item.sourceType = PlayHistoryItem.SOURCE_LOCAL;
    return item;
  }
}
