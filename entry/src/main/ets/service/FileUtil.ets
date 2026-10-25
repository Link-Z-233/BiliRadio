import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Constants } from './Constants';

// 公共文件读写工具：全库唯一实现，供 AppStore 等复用。
// 仅依赖 @kit.CoreFileKit / @kit.ArkTS / Constants（自身零业务依赖）；自身不吞异常，由调用方 try-catch 兜底。
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

  // 用户文件 URI 读取：分块读整文件（不依赖 statSync 对 user URI 的兼容性，plan D8），异常向上抛
  static readTextFromUri(uri: string): string {
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const chunks: Uint8Array[] = [];
      let total: number = 0;
      while (true) {
        const buf: ArrayBuffer = new ArrayBuffer(Constants.URI_READ_CHUNK_BYTES);
        const readBytes: number = fs.readSync(file.fd, buf);
        if (readBytes <= 0) {
          break;
        }
        chunks.push(new Uint8Array(buf, 0, readBytes));
        total += readBytes;
        if (readBytes < Constants.URI_READ_CHUNK_BYTES) {
          break;
        }
      }
      if (total === 0) {
        return '';
      }
      const all: Uint8Array = new Uint8Array(total);
      let offset: number = 0;
      for (const chunk of chunks) {
        all.set(chunk, offset);
        offset += chunk.length;
      }
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(all);
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