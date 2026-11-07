import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

// B站 WBI 签名：polymer 系列接口（合集/追更等）的通用鉴权参数。
// 算法：从 nav 接口 wbi_img.img_url/sub_url 的文件名拼出原始 key，
// 按固定 mixinKeyEncTab 表重排取前 32 位得到 mixinKey；
// 参数含 wts 时间戳一并排序(过滤 !'()* 后)拼 query，
// MD5(query + mixinKey) 得 w_rid（wts 必须参与签名，漏签即 -403）。
const MIXIN_KEY_ENC_TAB: number[] = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
  27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
  37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
  22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
];

export class WbiSigner {
  static getMixinKey(imgUrl: string, subUrl: string): string {
    const raw: string = WbiSigner.extractKey(imgUrl) + WbiSigner.extractKey(subUrl);
    let mixin: string = '';
    for (let i = 0; i < 32; i++) {
      const idx: number = MIXIN_KEY_ENC_TAB[i];
      if (idx < raw.length) {
        mixin += raw.charAt(idx);
      }
    }
    return mixin;
  }

  private static extractKey(url: string): string {
    const parts: string[] = url.split('/');
    const last: string = parts[parts.length - 1];
    const dot: number = last.indexOf('.');
    return dot >= 0 ? last.substring(0, dot) : last;
  }

  static async signParams(params: Record<string, string>, mixinKey: string): Promise<string> {
    const wts: string = Math.floor(Date.now() / 1000).toString();
    const keys: string[] = Object.keys(params);
    keys.push('wts');
    keys.sort();
    let query: string = '';
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const rawV: string = k === 'wts' ? wts : params[k];
      const v: string = rawV.replace(/[!'()*]/g, '');
      if (query !== '') {
        query += '&';
      }
      query += encodeURIComponent(k) + '=' + encodeURIComponent(v);
    }
    const wRid: string = await WbiSigner.md5(query + mixinKey);
    return query + '&w_rid=' + wRid;
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