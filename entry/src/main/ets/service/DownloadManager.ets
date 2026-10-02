import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DownloadedSong } from '../model/DownloadedSong';
import { BiliService, DownloadProgressCallback } from './BiliService';
import { Constants } from './Constants';
import { FileUtil } from './FileUtil';

// 离线下载管理器：把用户主动下载的歌曲持久保存到 filesDir/downloads/，独立于
// cacheDir 的「临时播放缓存」（后者播完即清、受容量上限 LRU 控制）。
// 已下载清单持久化到 filesDir/downloads.json，结构复用 AppStore 的 JSON 模式。
export class DownloadManager {
  private static instance: DownloadManager | undefined = undefined;
  private songs: DownloadedSong[] = [];
  private loaded: boolean = false;

  static getInstance(): DownloadManager {
    if (DownloadManager.instance === undefined) {
      DownloadManager.instance = new DownloadManager();
    }
    return DownloadManager.instance;
  }

  // 已下载清单（懒加载）；外部修改后调用 notifyChanged 触发订阅刷新
  get downloads(): DownloadedSong[] {
    if (!this.loaded) {
      this.load();
    }
    return this.songs;
  }

  private downloadsDir(): string {
    const context = getContext() as common.UIAbilityContext;
    return `${context.filesDir}/downloads`;
  }

  private listPath(): string {
    const context = getContext() as common.UIAbilityContext;
    return `${context.filesDir}/downloads.json`;
  }

  private ensureDir(): void {
    const dir: string = this.downloadsDir();
    if (!fs.accessSync(dir)) {
      try {
        fs.mkdirSync(dir);
      } catch (e) {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'mkdir downloads failed');
      }
    }
  }

  private findByBvid(bvid: string): DownloadedSong | undefined {
    if (!this.loaded) {
      this.load();
    }
    for (let i = 0; i < this.songs.length; i++) {
      if (this.songs[i].bvid === bvid) {
        return this.songs[i];
      }
    }
    return undefined;
  }

  isDownloaded(bvid: string): boolean {
    return this.findByBvid(bvid) !== undefined;
  }

  // 返回已下载音频的本地路径；未下载或文件已丢失返回空串
  resolveLocalPath(bvid: string): string {
    const song: DownloadedSong | undefined = this.findByBvid(bvid);
    if (song === undefined) {
      return '';
    }
    try {
      if (song.localPath !== '' && fs.accessSync(song.localPath)) {
        return song.localPath;
      }
    } catch (e) {}
    return '';
  }

  // 下载单曲到本地（已下载则直接返回）。onProgress 透传下载进度。
  async downloadSong(bvid: string, onProgress?: DownloadProgressCallback): Promise<DownloadedSong> {
    if (!this.loaded) {
      this.load();
    }
    const existing: DownloadedSong | undefined = this.findByBvid(bvid);
    if (existing !== undefined && this.resolveLocalPath(bvid) !== '') {
      return existing;
    }
    const video = await BiliService.fetchVideoInfo(bvid);
    this.ensureDir();
    let localPath: string = '';
    try {
      const candidates: string[] = await BiliService.fetchDashAudioCandidates(video.bvid, video.cid);
      localPath = await BiliService.downloadFirstSuccessToFile(
        candidates, `${this.downloadsDir()}/${video.bvid}.m4a`, onProgress);
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'dash audio failed, fallback to durl mp4');
      const durlCandidates: string[] = await BiliService.fetchDurlCandidates(video.bvid, video.cid);
      localPath = await BiliService.downloadFirstSuccessToFile(
        durlCandidates, `${this.downloadsDir()}/${video.bvid}.mp4`, onProgress);
    }
    const size: number = fs.statSync(localPath).size;
    const song: DownloadedSong = DownloadedSong.fromVideo(video, localPath, size, Date.now());
    this.songs.push(song);
    this.save();
    return song;
  }

  // 删除已下载歌曲（可多首）：移除清单并删除本地文件
  deleteDownloads(bvids: string[]): number {
    if (!this.loaded) {
      this.load();
    }
    let removed: number = 0;
    const kept: DownloadedSong[] = [];
    for (let i = 0; i < this.songs.length; i++) {
      if (bvids.indexOf(this.songs[i].bvid) >= 0) {
        try {
          if (this.songs[i].localPath !== '') {
            fs.unlinkSync(this.songs[i].localPath);
          }
        } catch (e) {}
        removed++;
      } else {
        kept.push(this.songs[i]);
      }
    }
    if (removed > 0) {
      this.songs = kept;
      this.save();
    }
    return removed;
  }

  downloadSizeMB(): number {
    if (!this.loaded) {
      this.load();
    }
    let total: number = 0;
    for (let i = 0; i < this.songs.length; i++) {
      total += this.songs[i].size;
    }
    return total / Constants.BYTES_PER_MB;
  }

  private load(): void {
    this.loaded = true;
    this.songs = [];
    try {
      const path: string = this.listPath();
      if (!fs.accessSync(path)) {
        return;
      }
      const content: string = FileUtil.readTextFile(path);
      if (content === '') {
        return;
      }
      const root: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      if (root['items'] !== undefined) {
        const itemRecords: Object[] = root['items'] as Object[];
        for (let i = 0; i < itemRecords.length; i++) {
          const rec: Record<string, Object> = itemRecords[i] as Record<string, Object>;
          const song: DownloadedSong = DownloadedSong.fromRecord(rec);
          // 文件已丢失的条目不再保留
          try {
            if (song.localPath === '' || !fs.accessSync(song.localPath)) {
              continue;
            }
          } catch (e) {
            continue;
          }
          this.songs.push(song);
        }
      }
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'load downloads failed');
    }
  }

  private save(): void {
    try {
      const itemRecords: Array<Record<string, Object>> = [];
      for (let i = 0; i < this.songs.length; i++) {
        itemRecords.push(this.songs[i].toRecord());
      }
      const rec: Record<string, Object> = {
        'items': itemRecords,
      };
      FileUtil.writeTextFile(this.listPath(), JSON.stringify(rec));
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'save downloads failed');
    }
  }

}