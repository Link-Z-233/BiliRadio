export class Season {
  seasonId: number = 0;
  title: string = '';
  count: number = 0;

  constructor(seasonId: number, title: string, count: number) {
    this.seasonId = seasonId;
    this.title = title;
    this.count = count;
  }
}