export class FavFolder {
  mediaId: number = 0;
  title: string = '';
  count: number = 0;

  constructor(mediaId: number, title: string, count: number) {
    this.mediaId = mediaId;
    this.title = title;
    this.count = count;
  }
}
