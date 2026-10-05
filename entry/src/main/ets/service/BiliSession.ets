export class BiliSession {
  private static instance: BiliSession | undefined = undefined;

  static getInstance(): BiliSession {
    if (BiliSession.instance === undefined) {
      BiliSession.instance = new BiliSession();
    }
    return BiliSession.instance;
  }

  cookieString: string = '';
  sessdata: string = '';
  biliJct: string = '';
  mid: number = 0;
  uname: string = '';
  buvid3: string = '';
  buvid4: string = '';
  // b_nut（风控指纹辅助字段，US3）：由响应 Set-Cookie 被动收集，随 Cookie 一并携带
  bNut: string = '';

  isLogged(): boolean {
    return this.sessdata !== '';
  }

  hasBuvid(): boolean {
    return this.buvid3 !== '';
  }

  setCookieString(raw: string): void {
    const cookie: string = raw.trim();
    this.cookieString = cookie;
    this.sessdata = BiliSession.extractValue(cookie, 'SESSDATA');
    this.biliJct = BiliSession.extractValue(cookie, 'bili_jct');
  }

  // 被动收集响应 Set-Cookie 中的 b_nut（US3）：仅在解析出非空值时覆写
  collectSetCookie(setCookie: string): void {
    if (setCookie === '') {
      return;
    }
    // Set-Cookie 可能多条以逗号/换行拼接，统一归一为分号分隔后提取
    const normalized: string = setCookie.split(',').join(';').split('\n').join(';');
    const value: string = BiliSession.extractValue(normalized, 'b_nut');
    if (value !== '') {
      this.bNut = value;
    }
  }

  clear(): void {
    this.cookieString = '';
    this.sessdata = '';
    this.biliJct = '';
    this.mid = 0;
    this.uname = '';
  }

  resetBuvid(): void {
    this.buvid3 = '';
    this.buvid4 = '';
    this.bNut = '';
  }

  private static extractValue(cookie: string, key: string): string {
    const parts: string[] = cookie.split(';');
    for (let i = 0; i < parts.length; i++) {
      const p: string = parts[i].trim();
      if (p.indexOf(key + '=') === 0) {
        return p.substring(key.length + 1);
      }
    }
    return '';
  }
}
