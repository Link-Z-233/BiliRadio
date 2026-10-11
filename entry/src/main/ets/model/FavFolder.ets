@ObservedV2
export class FavFolder {
  @Trace mediaId: number = 0;
  @Trace title: string = '';
  @Trace count: number = 0;

  constructor(mediaId: number, title: string, count: number) {
    this.mediaId = mediaId;
    this.title = title;
    this.count = count;
  }
}
