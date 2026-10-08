import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { Constants } from './Constants';

export class AppSigner {
  static async signQuery(params: Record<string, string>): Promise<string> {
    const merged: Record<string, string> = {
      'appkey': Constants.TV_APP_KEY,
      'ts': Math.floor(Date.now() / 1000).toString(),
    };
    const keys: string[] = Object.keys(params);
    for (let i: number = 0; i < keys.length; i++) {
      merged[keys[i]] = params[keys[i]];
    }
    const sorted: string[] = Object.keys(merged).sort();
    let query: string = '';
    for (let i: number = 0; i < sorted.length; i++) {
      const k: string = sorted[i];
      if (query !== '') {
        query += '&';
      }
      query += encodeURIComponent(k) + '=' + encodeURIComponent(merged[k]);
    }
    const sign: string = await AppSigner.md5(query + Constants.TV_APP_SEC);
    return `${query}&sign=${sign}`;
  }

  private static async md5(input: string): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    const encoder: util.TextEncoder = new util.TextEncoder();
    const data: Uint8Array = encoder.encodeInto(input);
    const blob: cryptoFramework.DataBlob = { data: data };
    await md.update(blob);
    const out: cryptoFramework.DataBlob = await md.digest();
    let hex: string = '';
    for (let i = 0; i < out.data.length; i++) {
      const b: number = out.data[i];
      hex += (b < 16 ? '0' : '') + b.toString(16);
    }
    return hex;
  }
}
