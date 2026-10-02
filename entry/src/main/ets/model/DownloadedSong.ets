import { BiliVideo } from './BiliVideo';

// 已下载歌曲：持久化到本地（离线可播）的音频文件及其元数据。
// 元数据字段与 BiliVideo 对齐，便于「下载内容」来源直接作为歌曲源播放。
export class DownloadedSong {
  bvid: string = '';
  aid: number = 0;
  cid: number = 0;
  title: string = '';
  cover: string = '';
  duration: number = 0;
  ownerMid: number = 0;
  ownerName: string = '';
  ownerFace: string = '';
  view: number = 0;
  pubdate: number = 0;
  desc: string = '';
  localPath: string = '';
  size: number = 0;
  downloadTime: number = 0;

  static fromVideo(video: BiliVideo, localPath: string, size: number, downloadTime: number): DownloadedSong {
    const s = new DownloadedSong();
    s.bvid = video.bvid;
    s.aid = video.aid;
    s.cid = video.cid;
    s.title = video.title;
    s.cover = video.cover;
    s.duration = video.duration;
    s.ownerMid = video.ownerMid;
    s.ownerName = video.ownerName;
    s.ownerFace = video.ownerFace;
    s.view = video.view;
    s.pubdate = video.pubdate;
    s.desc = video.desc;
    s.localPath = localPath;
    s.size = size;
    s.downloadTime = downloadTime;
    return s;
  }

  toRecord(): Record<string, Object> {
    const rec: Record<string, Object> = {
      'bvid': this.bvid,
      'aid': this.aid,
      'cid': this.cid,
      'title': this.title,
      'cover': this.cover,
      'duration': this.duration,
      'ownerMid': this.ownerMid,
      'ownerName': this.ownerName,
      'ownerFace': this.ownerFace,
      'view': this.view,
      'pubdate': this.pubdate,
      'desc': this.desc,
      'localPath': this.localPath,
      'size': this.size,
      'downloadTime': this.downloadTime,
    };
    return rec;
  }

  static fromRecord(rec: Record<string, Object>): DownloadedSong {
    const s = new DownloadedSong();
    if (rec['bvid'] !== undefined) {
      s.bvid = rec['bvid'] as string;
    }
    if (rec['aid'] !== undefined) {
      s.aid = rec['aid'] as number;
    }
    if (rec['cid'] !== undefined) {
      s.cid = rec['cid'] as number;
    }
    if (rec['title'] !== undefined) {
      s.title = rec['title'] as string;
    }
    if (rec['cover'] !== undefined) {
      s.cover = rec['cover'] as string;
    }
    if (rec['duration'] !== undefined) {
      s.duration = rec['duration'] as number;
    }
    if (rec['ownerMid'] !== undefined) {
      s.ownerMid = rec['ownerMid'] as number;
    }
    if (rec['ownerName'] !== undefined) {
      s.ownerName = rec['ownerName'] as string;
    }
    if (rec['ownerFace'] !== undefined) {
      s.ownerFace = rec['ownerFace'] as string;
    }
    if (rec['view'] !== undefined) {
      s.view = rec['view'] as number;
    }
    if (rec['pubdate'] !== undefined) {
      s.pubdate = rec['pubdate'] as number;
    }
    if (rec['desc'] !== undefined) {
      s.desc = rec['desc'] as string;
    }
    if (rec['localPath'] !== undefined) {
      s.localPath = rec['localPath'] as string;
    }
    if (rec['size'] !== undefined) {
      s.size = rec['size'] as number;
    }
    if (rec['downloadTime'] !== undefined) {
      s.downloadTime = rec['downloadTime'] as number;
    }
    return s;
  }

  toBiliVideo(): BiliVideo {
    const v = new BiliVideo();
    v.bvid = this.bvid;
    v.aid = this.aid;
    v.cid = this.cid;
    v.title = this.title;
    v.cover = this.cover;
    v.duration = this.duration;
    v.ownerMid = this.ownerMid;
    v.ownerName = this.ownerName;
    v.ownerFace = this.ownerFace;
    v.view = this.view;
    v.pubdate = this.pubdate;
    v.desc = this.desc;
    v.audioUrl = this.localPath;
    return v;
  }
}