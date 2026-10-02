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

  clear(): void {
    this.cookieString = '';
    this.sessdata = '';
    this.biliJct = '';
    this.mid = 0;
    this.uname = '';
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
