// 封面缩略图：播放列表与播放历史共用的封面渲染（有封面显示图片，无封面显示 ♪ 占位）。
@Component
export struct CoverThumb {
  cover: string = '';
  thumbSize: number = 44;
  radius: number = 8;
  highlight: boolean = false;

  // 缩略图只有 44vp，却直接解码 B 站原图（常见 1920×1080）会让位图内存相差 30 倍以上。
  // 这里给 CDN 图片拼接尺寸后缀，让服务端下发小图：@宽w_高h_1c(居中裁切).webp
  private thumbUrl(): string {
    const url: string = this.cover;
    if (url === '' || url.indexOf('hdslb.com') < 0 || url.indexOf('@') >= 0) {
      return url;
    }
    const q: number = url.indexOf('?');
    const base: string = q >= 0 ? url.substring(0, q) : url;
    const query: string = q >= 0 ? url.substring(q) : '';
    return `${base}@240w_240h_1c.webp${query}`;
  }

  build() {
    if (this.cover !== '') {
      Image(this.thumbUrl())
        .width(this.thumbSize)
        .height(this.thumbSize)
        .borderRadius(this.radius)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.startIcon'))
        .border(this.highlight ? { width: 2, color: $r('app.color.primary_color') } : { width: 0 })
    } else {
      Column() {
        Text('♪')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(this.thumbSize)
      .height(this.thumbSize)
      .borderRadius(this.radius)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.btn_glass'))
      .border(this.highlight
        ? { width: 2, color: $r('app.color.primary_color') }
        : { width: 1, color: $r('app.color.btn_border') })
    }
  }
}