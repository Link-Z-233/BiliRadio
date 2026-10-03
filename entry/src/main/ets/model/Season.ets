export class Season {
  seasonId: number = 0;
  title: string = '';
  count: number = 0;
  cover: string = '';

  constructor(seasonId: number, title: string, count: number, cover: string = '') {
    this.seasonId = seasonId;
    this.title = title;
    this.count = count;
    this.cover = cover;
  }
}