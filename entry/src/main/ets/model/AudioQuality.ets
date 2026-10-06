// 音质档位与音轨模型（audio-quality-settings）：
// QualityTier 四档枚举（数值即 B 站 qn 码）+ AudioTrack 音轨模型 + 档位映射/标签纯静态工具。
// 被 service（BiliService/PlayerController）与 pages（SettingsPage/PlayerOverlay）双侧引用，
// 独立成 model 文件避免 service↔pages 反向依赖；静态方法不使用 this。

export enum QualityTier {
  MAX = 0,      // 最高：取最高可用档，含 Hi-Res/杜比升级（无固定 qn）
  Q192K = 30280,
  Q132K = 30232,
  Q64K = 30216
}

// playurl DASH 响应中的单条音轨：id 为 B 站档位码（flac/dolby 解析时补 30251/30250，durl 兜底为 0）
export class AudioTrack {
  id: number;
  bandwidth: number;
  urls: string[];

  constructor(id: number, bandwidth: number, urls: string[]) {
    this.id = id;
    this.bandwidth = bandwidth;
    this.urls = urls;
  }
}

// resolveAudioTrack 的解析结果：id/urls 为选中音轨，tracks 为 dash 全量可用音轨（durl 兜底为空数组），
// source 标记来源（'dash' | 'durl'），供 playIndex/setQualityTier 记录音质状态
export class ResolvedAudio {
  id: number;
  urls: string[];
  tracks: AudioTrack[];
  source: string;

  constructor(id: number, urls: string[], tracks: AudioTrack[], source: string) {
    this.id = id;
    this.urls = urls;
    this.tracks = tracks;
    this.source = source;
  }
}

export class AudioQuality {
  // 存储值归一（FR-001）：仅接受合法档位值，非法/未初始化（-1）回落 MAX
  static fromStored(n: number): QualityTier {
    if (n === QualityTier.Q192K) {
      return QualityTier.Q192K;
    }
    if (n === QualityTier.Q132K) {
      return QualityTier.Q132K;
    }
    if (n === QualityTier.Q64K) {
      return QualityTier.Q64K;
    }
    return QualityTier.MAX;
  }

  // 档位显示名
  static label(tier: QualityTier): string {
    if (tier === QualityTier.Q192K) {
      return '192K';
    }
    if (tier === QualityTier.Q132K) {
      return '132K';
    }
    if (tier === QualityTier.Q64K) {
      return '64K';
    }
    return '最高';
  }

  // 音轨码→档位写回映射（FR-004）：Hi-Res(30251)/杜比(30250) 仅能经「最高」档到达，写回 MAX
  static tierOfTrackId(id: number): QualityTier {
    if (id === QualityTier.Q192K) {
      return QualityTier.Q192K;
    }
    if (id === QualityTier.Q132K) {
      return QualityTier.Q132K;
    }
    if (id === QualityTier.Q64K) {
      return QualityTier.Q64K;
    }
    return QualityTier.MAX;
  }

  // 音轨码显示名（US3 面板列表）：未知码回落「默认」
  static trackLabel(id: number): string {
    if (id === 30251) {
      return 'Hi-Res';
    }
    if (id === 30250) {
      return '杜比';
    }
    if (id === QualityTier.Q192K) {
      return '192K';
    }
    if (id === QualityTier.Q132K) {
      return '132K';
    }
    if (id === QualityTier.Q64K) {
      return '64K';
    }
    return '默认';
  }
}
