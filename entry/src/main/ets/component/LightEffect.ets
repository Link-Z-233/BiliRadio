import { hdsEffect } from '@kit.UIDesignKit';
import { uiEffect } from '@kit.ArkGraphics2D';


export function noLightEffect(): uiEffect.VisualEffect {
  return new hdsEffect.HdsEffectBuilder()
    .pointLight({ sourceType: hdsEffect.PointLightSourceType.NONE })
    .buildEffect();
}

export function illuminatedEffect(): uiEffect.VisualEffect {
  return new hdsEffect.HdsEffectBuilder()
    .pointLight({
      sourceType: hdsEffect.PointLightSourceType.NONE,
      illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER
    })
    .buildEffect();
}

export function lightSourceEffect(): uiEffect.VisualEffect {
  return new hdsEffect.HdsEffectBuilder()
    .pointLight({
      sourceType: hdsEffect.PointLightSourceType.BRIGHT,
      illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER
    })
    .buildEffect();
}

export function softSourceEffect(): uiEffect.VisualEffect {
  return new hdsEffect.HdsEffectBuilder()
    .pointLight({
      sourceType: hdsEffect.PointLightSourceType.SOFT,
      illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER
    })
    .buildEffect();
}

// 液态点光源：强度连续可调，边框与内容同时照亮
// force 取值 0~1，映射到 0~5 的推荐光照强度区间；
// 按压时把 force 用 animateTo 逐帧过渡，即可形成"光液流动"的沉浸光感。
export function liquidLightEffect(force: number, height: number = 140, bloom: number = 0.4): uiEffect.VisualEffect {
  const intensity: number = force * 5;
  return new hdsEffect.HdsEffectBuilder()
    .pointLight({
      sourceType: hdsEffect.PointLightSourceType.SOFT,
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      options: {
        intensity: intensity,
        height: height,
        bloom: bloom
      }
    })
    .buildEffect();
}

