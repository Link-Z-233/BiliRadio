import { image } from '@kit.ImageKit';

// 封面亮度抽样边长：缩到 16x16 再算平均，兼顾速度与准确
const SAMPLE_SIZE: number = 16;
const FALLBACK_BRIGHTNESS: number = 128;

// 封面明暗分析：读取封面平均亮度（0~255），用于智能反色（背景暗则前景转浅色、背景亮则前景转深色）
export class CoverAnalyzer {
  static async averageBrightness(url: string): Promise<number> {
    try {
      const src: image.ImageSource = image.createImageSource(url);
      const pm: image.PixelMap = await src.createPixelMap({
        desiredSize: { width: SAMPLE_SIZE, height: SAMPLE_SIZE }
      });
      const info: image.ImageInfo = await pm.getImageInfo();
      const w: number = info.size.width;
      const h: number = info.size.height;
      const buf: ArrayBuffer = new ArrayBuffer(w * h * 4);
      await pm.readPixelsToBuffer(buf);
      // readPixelsToBuffer 输出为 BGRA_8888 顺序
      const bytes: Uint8Array = new Uint8Array(buf);
      let sum: number = 0;
      let count: number = 0;
      const len: number = bytes.length;
      for (let i = 0; i < len; i += 4) {
        const b: number = bytes[i];
        const g: number = bytes[i + 1];
        const r: number = bytes[i + 2];
        sum += 0.299 * r + 0.587 * g + 0.114 * b;
        count++;
      }
      if (count === 0) {
        return FALLBACK_BRIGHTNESS;
      }
      return sum / count;
    } catch (e) {
      return FALLBACK_BRIGHTNESS;
    }
  }
}