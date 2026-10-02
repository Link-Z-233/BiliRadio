import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// 公共文件读写工具：全库唯一实现，供 AppStore / DownloadManager 等复用。
// 仅依赖 @kit.CoreFileKit / @kit.ArkTS，零业务依赖；自身不吞异常，由调用方 try-catch 兜底。
export class FileUtil {
  static readTextFile(path: string): string {
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = fs.statSync(path);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      const readBytes: number = fs.readSync(file.fd, buf);
      if (readBytes > 0) {
        const bytes: Uint8Array = new Uint8Array(buf, 0, readBytes);
        const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
        return decoder.decodeToString(bytes);
      }
      return '';
    } finally {
      fs.closeSync(file);
    }
  }

  static writeTextFile(path: string, content: string): void {
    const file: fs.File = fs.openSync(path,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
  }

  static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }
}