@ObservedV2
export class BiliVideo {
  @Trace bvid: string = '';
  @Trace aid: number = 0;
  @Trace cid: number = 0;
  @Trace title: string = '';
  @Trace cover: string = '';
  @Trace duration: number = 0;
  @Trace folderIds: number[] = [];
  @Trace seasonKeys: string[] = [];
  @Trace ownerMid: number = 0;
  @Trace ownerName: string = '';
  @Trace ownerFace: string = '';
  @Trace view: number = 0;
  @Trace pubdate: number = 0;
  @Trace desc: string = '';
  @Trace page: number = 0;
  @Trace partTitle: string = '';
  @Trace videoTitle: string = '';
  @Trace isUpowerExclusive: boolean = false;
  @Trace folderOwnerMid: number = 0;

  static create(bvid: string, aid: number, cid: number, title: string, cover: string, duration: number): BiliVideo {
    const v = new BiliVideo();
    v.bvid = bvid;
    v.aid = aid;
    v.cid = cid;
    v.title = title;
    v.cover = cover;
    v.duration = duration;
    return v;
  }

  toRecord(): Record<string, Object> {
    const rec: Record<string, Object> = {
      'bvid': this.bvid,
      'aid': this.aid,
      'cid': this.cid,
      'title': this.title,
      'cover': this.cover,
      'duration': this.duration,
      'folderIds': this.folderIds,
      'seasonKeys': this.seasonKeys,
      'ownerMid': this.ownerMid,
      'ownerName': this.ownerName,
      'ownerFace': this.ownerFace,
      'view': this.view,
      'pubdate': this.pubdate,
      'desc': this.desc,
      'page': this.page,
      'partTitle': this.partTitle,
      'videoTitle': this.videoTitle,
      'isUpowerExclusive': this.isUpowerExclusive,
      'folderOwnerMid': this.folderOwnerMid,
    };
    return rec;
  }

  static fromRecord(rec: Record<string, Object>): BiliVideo {
    const v = new BiliVideo();
    if (rec['bvid'] !== undefined) {
      v.bvid = rec['bvid'] as string;
    }
    if (rec['aid'] !== undefined) {
      v.aid = rec['aid'] as number;
    }
    if (rec['cid'] !== undefined) {
      v.cid = rec['cid'] as number;
    }
    if (rec['title'] !== undefined) {
      v.title = rec['title'] as string;
    }
    if (rec['cover'] !== undefined) {
      v.cover = rec['cover'] as string;
    }
    if (rec['duration'] !== undefined) {
      v.duration = rec['duration'] as number;
    }
    if (rec['folderIds'] !== undefined) {
      v.folderIds = rec['folderIds'] as number[];
    }
    if (rec['seasonKeys'] !== undefined) {
      v.seasonKeys = rec['seasonKeys'] as string[];
    }
    if (rec['ownerMid'] !== undefined) {
      v.ownerMid = rec['ownerMid'] as number;
    }
    if (rec['ownerName'] !== undefined) {
      v.ownerName = rec['ownerName'] as string;
    }
    if (rec['ownerFace'] !== undefined) {
      v.ownerFace = rec['ownerFace'] as string;
    }
    if (rec['view'] !== undefined) {
      v.view = rec['view'] as number;
    }
    if (rec['pubdate'] !== undefined) {
      v.pubdate = rec['pubdate'] as number;
    }
    if (rec['desc'] !== undefined) {
      v.desc = rec['desc'] as string;
    }
    if (rec['page'] !== undefined) {
      v.page = rec['page'] as number;
    }
    if (rec['partTitle'] !== undefined) {
      v.partTitle = rec['partTitle'] as string;
    }
    if (rec['videoTitle'] !== undefined) {
      v.videoTitle = rec['videoTitle'] as string;
    }
    if (rec['isUpowerExclusive'] !== undefined) {
      v.isUpowerExclusive = rec['isUpowerExclusive'] as boolean;
    }
    if (rec['folderOwnerMid'] !== undefined) {
      v.folderOwnerMid = rec['folderOwnerMid'] as number;
    }
    if (v.videoTitle === '') {
      v.videoTitle = v.title;
    }
    if (v.page <= 0 && v.cid > 0) {
      v.page = 1;
    }
    return v;
  }

  // 来源类别推导：0=个人收藏夹 1=UP主合集 2=本地内容（与 PlayHistoryItem.SOURCE_* 语义对齐）
  sourceType(): number {
    if (this.folderIds.length > 0) {
      return 0;
    }
    if (this.seasonKeys.length > 0) {
      return 1;
    }
    return 2;
  }

  // 来源中文标签的唯一映射点：0=个人收藏夹 1=UP主合集 其余=本地内容
  static sourceLabelOf(type: number): string {
    if (type === 0) {
      return '个人收藏夹';
    }
    if (type === 1) {
      return 'UP主合集';
    }
    return '本地内容';
  }

  sourceLabel(): string {
    return BiliVideo.sourceLabelOf(this.sourceType());
  }

  static composePartTitle(videoTitle: string, page: number, partTitle: string, isMultiPart: boolean): string {
    if (!isMultiPart) {
      return videoTitle;
    }
    if (partTitle !== '' && partTitle !== videoTitle) {
      return `${videoTitle} · P${page} ${partTitle}`;
    }
    return `${videoTitle} · P${page}`;
  }

  static itemKeyOf(bvid: string, page: number): string {
    const normalized = page > 0 ? page : 1;
    return `${bvid}:${normalized}`;
  }
}
