import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from './Constants';
import { CoverUrl } from './CoverUrl';

/**
 * 播放页封面取色（palette-glow/palette-bg）：
 * - dominantOf(bvid, rawCover)：下载封面 → 小图解码 → ColorPicker 择优主色（占比色优先，灰/暗降级高饱和色）→ '#RRGGBB'；
 *   bvid 为缓存键（同视频封面不变），并发去重，失败不缓存（下次重试）。
 * - washTint：背景衍生色——保留色相、饱和度压至 10-20%、明度定至近白/近黑（浅/深外观），
 *   播放页背景渐变据此柔和适配封面色系（幅度有限）；光晕基色直接用择优主色。
 * - 取色失败由调用方回退主题色，本类不感知 UI 状态。
 */
export class CoverPalette {
  private static cache: Map<string, string> = new Map<string, string>();
  private static inFlight: Map<string, Promise<string>> = new Map<string, Promise<string>>();

  static dominantOf(bvid: string, rawCover: string): Promise<string> {
    if (bvid === '' || rawCover === '') {
      return Promise.resolve('');
    }
    const hit: string | undefined = CoverPalette.cache.get(bvid);
    if (hit !== undefined) {
      return Promise.resolve(hit);
    }
    const flying: Promise<string> | undefined = CoverPalette.inFlight.get(bvid);
    if (flying !== undefined) {
      return flying;
    }
    const fetchUrl: string = CoverUrl.sized(rawCover, Constants.PALETTE_FETCH_W, Constants.PALETTE_FETCH_H);
    const task: Promise<string> = CoverPalette.extract(fetchUrl);
    CoverPalette.inFlight.set(bvid, task);
    task.then((hex: string): void => {
      CoverPalette.inFlight.delete(bvid);
      // ponytail: 缓存满即整体清空，极端情况多取一次色；LRU 淘汰在 24 条量级无感知收益
      if (CoverPalette.cache.size >= Constants.PALETTE_CACHE_MAX) {
        CoverPalette.cache.clear();
      }
      CoverPalette.cache.set(bvid, hex);
    }).catch((): void => {
      CoverPalette.inFlight.delete(bvid);
    });
    return task;
  }

  // 背景衍生色（palette-bg）：保留色相、饱和度压至 10-20%、明度定至近白（浅色外观）/近黑（深色外观），
  // 背景柔和适配封面色系但幅度有限（不抢内容）
  static washTint(hex: string, dark: boolean): string {
    const channels: number[] = CoverPalette.hexChannels(hex);
    if (channels.length === 0) {
      return '';
    }
    const max: number = Math.max(channels[0], channels[1], channels[2]);
    const min: number = Math.min(channels[0], channels[1], channels[2]);
    const lTarget: number = dark ? Constants.PALETTE_BG_L_DARK : Constants.PALETTE_BG_L_LIGHT;
    if (max === min) {
      return CoverPalette.hslHex(0, 0, lTarget);
    }
    const l: number = (max + min) / 510;
    const s: number = Math.min(Math.max(CoverPalette.rawSat(l, max, min), Constants.PALETTE_BG_SAT_MIN), Constants.PALETTE_BG_SAT_MAX);
    const h: number = CoverPalette.rgbHue(channels[0], channels[1], channels[2], max, min);
    return CoverPalette.hslHex(h, s, lTarget);
  }

  // 光晕基色（palette-glow）：浅色外观直接用取色原色；深色外观保留色相/饱和度、明度压至暗调，
  // 避免浅色封面（白底/浅色主色）在深色页面上形成浅色光斑；纯灰白无色调返回 ''，
  // 由调用方回退主题色，保证深色光晕始终彩色
  static glowTint(hex: string, dark: boolean): string {
    if (!dark) {
      return hex;
    }
    const channels: number[] = CoverPalette.hexChannels(hex);
    if (channels.length === 0) {
      return '';
    }
    const max: number = Math.max(channels[0], channels[1], channels[2]);
    const min: number = Math.min(channels[0], channels[1], channels[2]);
    if (max === min) {
      return '';
    }
    const l: number = (max + min) / 510;
    const h: number = CoverPalette.rgbHue(channels[0], channels[1], channels[2], max, min);
    return CoverPalette.hslHex(h, CoverPalette.rawSat(l, max, min), Constants.PALETTE_GLOW_L_DARK);
  }

  // HSL 饱和度（0-1）：HSL 定义随明度分段的相对极差
  private static rawSat(l: number, max: number, min: number): number {
    return l < 0.5 ? (max - min) / (max + min) : (max - min) / (510 - max - min);
  }

  private static rgbHue(r: number, g: number, b: number, max: number, min: number): number {
    const d: number = max - min;
    if (max === r) {
      return 60 * (((g - b) / d % 6 + 6) % 6);
    }
    if (max === g) {
      return 60 * ((b - r) / d + 2);
    }
    return 60 * ((r - g) / d + 4);
  }

  private static hslHex(h: number, s: number, l: number): string {
    const c: number = (1 - Math.abs(2 * l - 1)) * s;
    const x: number = c * (1 - Math.abs((h / 60) % 2 - 1));
    const hp: number = Math.floor(h / 60) % 6;
    let r1: number = 0;
    let g1: number = 0;
    let b1: number = 0;
    if (hp === 0) {
      r1 = c;
      g1 = x;
    } else if (hp === 1) {
      r1 = x;
      g1 = c;
    } else if (hp === 2) {
      g1 = c;
      b1 = x;
    } else if (hp === 3) {
      g1 = x;
      b1 = c;
    } else if (hp === 4) {
      r1 = x;
      b1 = c;
    } else {
      r1 = c;
      b1 = x;
    }
    const m: number = l - c / 2;
    return CoverPalette.channelsHex([(r1 + m) * 255, (g1 + m) * 255, (b1 + m) * 255]);
  }

  private static async extract(url: string): Promise<string> {
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        usingCache: false,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: Constants.CONNECT_TIMEOUT_MS,
        readTimeout: Constants.READ_TIMEOUT_MS
      });
      const code: number = response.responseCode;
      if (code !== 200) {
        throw new Error(`HTTP ${code}`);
      }
      const buffer: ArrayBuffer = response.result as ArrayBuffer;
      if (buffer === undefined || buffer === null || buffer.byteLength === 0) {
        throw new Error('empty cover body');
      }
      const source: image.ImageSource = image.createImageSource(buffer);
      const pixelMap: image.PixelMap = await source.createPixelMap({
        desiredSize: { width: Constants.PALETTE_DECODE_W, height: Constants.PALETTE_DECODE_H }
      });
      await source.release();
      const picker: effectKit.ColorPicker = await effectKit.createColorPicker(pixelMap);
      const picked: effectKit.Color = CoverPalette.pickColor(picker);
      await pixelMap.release();
      if (picked === undefined || picked === null) {
        throw new Error('color pick failed');
      }
      const hex: string = CoverPalette.toHex(picked);
      if (hex === '') {
        throw new Error('color pick invalid');
      }
      return hex;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, `palette extract failed: ${e.message}`);
      throw new Error(`palette extract failed: ${e.message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  // 主色择优（黑灰底根因修复）：getMainColorSync 是缩图加权平均，封面带黑边/大暗部必出脏灰；
  // 改用中位切割占比色为主，占比色过灰（白/灰底封面）或过暗（黑底封面）时取最高饱和色；
  // 候选均不可用（纯黑白灰封面）时返回占比色原值，交归一化处理
  private static pickColor(picker: effectKit.ColorPicker): effectKit.Color {
    const proportion: effectKit.Color = picker.getLargestProportionColor();
    if (!CoverPalette.isColorUsable(proportion) || CoverPalette.colorLuma(proportion) < Constants.PALETTE_DARK_LUMA) {
      const vivid: effectKit.Color = picker.getHighestSaturationColor();
      if (CoverPalette.isColorUsable(vivid)) {
        return vivid;
      }
    }
    return proportion;
  }

  // 可用 = 非空、通道合法、非灰（RGB 通道极差达标）
  private static isColorUsable(c: effectKit.Color): boolean {
    if (c === undefined || c === null) {
      return false;
    }
    if (!(c.red >= 0 && c.red <= 255) || !(c.green >= 0 && c.green <= 255) || !(c.blue >= 0 && c.blue <= 255)) {
      return false;
    }
    const max: number = Math.max(c.red, c.green, c.blue);
    const min: number = Math.min(c.red, c.green, c.blue);
    return (max - min) >= Constants.PALETTE_GRAY_SPREAD;
  }

  private static colorLuma(c: effectKit.Color): number {
    return Math.round(0.299 * c.red + 0.587 * c.green + 0.114 * c.blue);
  }

  private static toHex(picked: effectKit.Color): string {
    const r: number = picked.red;
    const g: number = picked.green;
    const b: number = picked.blue;
    if (!(r >= 0 && r <= 255) || !(g >= 0 && g <= 255) || !(b >= 0 && b <= 255)) {
      return '';
    }
    return CoverPalette.channelsHex([r, g, b]);
  }

  private static hexChannels(hex: string): number[] {
    let normalized: string = hex.startsWith('#') ? hex.substring(1) : hex;
    if (!/^[0-9a-fA-F]{6}$/.test(normalized)) {
      return [];
    }
    return [
      parseInt(normalized.substring(0, 2), 16),
      parseInt(normalized.substring(2, 4), 16),
      parseInt(normalized.substring(4, 6), 16)
    ];
  }

  private static channelsHex(channels: number[]): string {
    const part = (v: number): string => {
      const rounded: number = Math.round(v);
      const clamped: number = rounded < 0 ? 0 : (rounded > 255 ? 255 : rounded);
      return clamped < 16 ? `0${clamped.toString(16)}` : clamped.toString(16);
    };
    return `#${part(channels[0])}${part(channels[1])}${part(channels[2])}`;
  }
}
