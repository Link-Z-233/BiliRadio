import { BiliVideo } from './BiliVideo';

export class UnfavoriteRecord {
  bvid: string = '';
  aid: number = 0;
  title: string = '';
  cover: string = '';
  duration: number = 0;
  folderIds: number[] = [];
  removedAt: number = 0;

  static fromVideo(video: BiliVideo, removedAt: number): UnfavoriteRecord {
    const r = new UnfavoriteRecord();
    r.bvid = video.bvid;
    r.aid = video.aid;
    r.title = video.title;
    r.cover = video.cover;
    r.duration = video.duration;
    r.folderIds = video.folderIds.slice(0);
    r.removedAt = removedAt;
    return r;
  }

  toRecord(): Record<string, Object> {
    const rec: Record<string, Object> = {
      'bvid': this.bvid,
      'aid': this.aid,
      'title': this.title,
      'cover': this.cover,
      'duration': this.duration,
      'folderIds': this.folderIds,
      'removedAt': this.removedAt,
    };
    return rec;
  }

  static fromRecord(rec: Record<string, Object>): UnfavoriteRecord {
    const r = new UnfavoriteRecord();
    if (rec['bvid'] !== undefined) {
      r.bvid = rec['bvid'] as string;
    }
    if (rec['aid'] !== undefined) {
      r.aid = rec['aid'] as number;
    }
    if (rec['title'] !== undefined) {
      r.title = rec['title'] as string;
    }
    if (rec['cover'] !== undefined) {
      r.cover = rec['cover'] as string;
    }
    if (rec['duration'] !== undefined) {
      r.duration = rec['duration'] as number;
    }
    if (rec['folderIds'] !== undefined) {
      r.folderIds = rec['folderIds'] as number[];
    }
    if (rec['removedAt'] !== undefined) {
      r.removedAt = rec['removedAt'] as number;
    }
    return r;
  }
}
