import { AppStorageV2 } from '@kit.ArkUI';

// V2 全局键基础设施：AppStorageV2 仅支持 object 类型，
// boolean/number/string 键一律经 @ObservedV2 包装类接入（同 key 全局共享实例，字段级双向）。
// 无参构造适配 TypeConstructorWithArgs 类型约束；初值经 defaultCreator 落位。

@ObservedV2
export class BoolState {
  @Trace value: boolean = false;
}

@ObservedV2
export class NumState {
  @Trace value: number = 0;
}

@ObservedV2
export class StrState {
  @Trace value: string = '';
}

export function connectBool(key: string, def: boolean): BoolState {
  const s: BoolState | undefined = AppStorageV2.connect(BoolState, key, (): BoolState => {
    const v: BoolState = new BoolState();
    v.value = def;
    return v;
  });
  return s !== undefined ? s : new BoolState();
}

export function connectNum(key: string, def: number): NumState {
  const s: NumState | undefined = AppStorageV2.connect(NumState, key, (): NumState => {
    const v: NumState = new NumState();
    v.value = def;
    return v;
  });
  return s !== undefined ? s : new NumState();
}

export function connectStr(key: string, def: string): StrState {
  const s: StrState | undefined = AppStorageV2.connect(StrState, key, (): StrState => {
    const v: StrState = new StrState();
    v.value = def;
    return v;
  });
  return s !== undefined ? s : new StrState();
}
