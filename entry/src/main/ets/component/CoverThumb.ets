import { CoverUrl } from '../service/CoverUrl';
import { Constants } from '../service/Constants';

// 封面缩略图：播放列表与播放历史共用的封面渲染（有封面显示图片，无封面显示 ♪ 占位——全类型唯一无图形态）。
@Component
export struct CoverThumb {
  @Prop cover: string = '';
  thumbSize: number = 44;
  radius: number = 8;
  highlight: boolean = false;
  // raw=true 直接加载原始 URL、不拼缩略后缀（UP 头像/合集封面等 URL 拼后缀会 404 的场景）；默认 false 行为不变
  raw: boolean = false;

  // 缩略图只有 44vp，却直接解码 B 站原图（常见 1920×1080）会让位图内存相差 30 倍以上。
  // 尺寸后缀逻辑收敛至 CoverUrl（US6），此处固定取缩略档 240×240
  private thumbUrl(): string {
    if (this.raw) {
      return this.cover;
    }
    return CoverUrl.sized(this.cover, Constants.COVER_THUMB_W, Constants.COVER_THUMB_H);
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