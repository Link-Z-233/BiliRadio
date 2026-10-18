import { CoverUrl } from '../service/CoverUrl';
import { Constants } from '../service/Constants';

// 封面缩略图：播放列表与播放历史共用的封面渲染（有封面显示图片，无封面显示耳机占位——全类型唯一无图形态）。
@Component
export struct CoverThumb {
  @Prop cover: string = '';
  thumbSize: number = Constants.LIST_THUMB_SIZE;
  radius: number = 8;
  // @Prop 化（v0.3-bugfix-round2 US4）：普通成员不随父组件切歌更新，高亮停留首帧是本根因
  @Prop highlight: boolean = false;
  // 高亮边框色（US4）：主题色运行时可变，由持有 StrState 的父方传入
  @Prop accent: string = Constants.ACCENT_DEFAULT;
  // raw=true 直接加载原始 URL、不拼缩略后缀（UP 头像/合集封面等 URL 拼后缀会 404 的场景）；默认 false 行为不变
  raw: boolean = false;
  // 宽高分离（v0.5-part1-source-page-redesign R1）：两者均 >0 时按 thumbWidth×thumbHeight 定尺寸（16:9 剧集行），
  // 缩略请求档换用 EPISODE_THUMB_REQ_*；否则回退 thumbSize 方形，既有调用点零改动
  thumbWidth: number = 0;
  thumbHeight: number = 0;

  private isWide(): boolean {
    return this.thumbWidth > 0 && this.thumbHeight > 0;
  }

  // 小尺寸列表缩略直解码 B 站原图（常见 1920×1080）位图内存相差 30 倍以上，
  // 尺寸后缀逻辑收敛至 CoverUrl（US6），方形走 240×240 档、16:9 走 EPISODE_THUMB_REQ 档
  private thumbUrl(): string {
    if (this.raw) {
      return this.cover;
    }
    if (this.isWide()) {
      return CoverUrl.sized(this.cover, Constants.EPISODE_THUMB_REQ_W, Constants.EPISODE_THUMB_REQ_H);
    }
    return CoverUrl.sized(this.cover, Constants.COVER_THUMB_W, Constants.COVER_THUMB_H);
  }

  build() {
    if (this.cover !== '') {
      Image(this.thumbUrl())
        .width(this.isWide() ? this.thumbWidth : this.thumbSize)
        .height(this.isWide() ? this.thumbHeight : this.thumbSize)
        .borderRadius(this.radius)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.startIcon'))
        .draggable(false)
        .border(this.highlight ? { width: 2, color: this.accent } : { width: 0 })
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.headphones'))
          .fontSize(this.isWide() ? this.thumbWidth / 2 : this.thumbSize / 2)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(this.isWide() ? this.thumbWidth : this.thumbSize)
      .height(this.isWide() ? this.thumbHeight : this.thumbSize)
      .borderRadius(this.radius)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.btn_glass'))
      .border(this.highlight
        ? { width: 2, color: this.accent }
        : { width: 1, color: $r('app.color.btn_border') })
    }
  }
}
