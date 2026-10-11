@ObservedV2
export class Season {
  @Trace seasonId: number = 0;
  @Trace title: string = '';
  @Trace count: number = 0;
  @Trace cover: string = '';

  constructor(seasonId: number, title: string, count: number, cover: string = '') {
    this.seasonId = seasonId;
    this.title = title;
    this.count = count;
    this.cover = cover;
  }
}