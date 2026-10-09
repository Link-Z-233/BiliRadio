// US6 CDN 封面尺寸后缀工具（唯一实现点）：hdslb.com 域、无 @、保留 query 才拼 @{w}w_{h}h_1c.webp；
// 非 hdslb / 已含 @ / 空串原样返回（raw 语义不回归，与既有 CoverThumb.thumbUrl 行为一致）
export class CoverUrl {
  static sized(url: string, w: number, h: number): string {
    if (url === '' || url.indexOf('hdslb.com') < 0 || url.indexOf('@') >= 0) {
      return url;
    }
    const q: number = url.indexOf('?');
    const base: string = q >= 0 ? url.substring(0, q) : url;
    const query: string = q >= 0 ? url.substring(q) : '';
    return `${base}@${w}w_${h}h_1c.webp${query}`;
  }
}
