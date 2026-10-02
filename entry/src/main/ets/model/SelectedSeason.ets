export class SelectedSeason {
  mid: number = 0;
  seasonId: number = 0;
  title: string = '';
  count: number = 0;

  constructor(mid: number, seasonId: number, title: string, count: number) {
    this.mid = mid;
    this.seasonId = seasonId;
    this.title = title;
    this.count = count;
  }

  // 合集唯一标识：mid + seasonId（不同 UP 主的 seasonId 可能重复，需联合定位）
  key(): string {
    return `${this.mid}_${this.seasonId}`;
  }

  toRecord(): Record<string, Object> {
    const rec: Record<string, Object> = {
      'mid': this.mid,
      'seasonId': this.seasonId,
      'title': this.title,
      'count': this.count,
    };
    return rec;
  }

  static fromRecord(rec: Record<string, Object>): SelectedSeason {
    const s = new SelectedSeason(0, 0, '', 0);
    if (rec['mid'] !== undefined) {
      s.mid = rec['mid'] as number;
    }
    if (rec['seasonId'] !== undefined) {
      s.seasonId = rec['seasonId'] as number;
    }
    if (rec['title'] !== undefined) {
      s.title = rec['title'] as string;
    }
    if (rec['count'] !== undefined) {
      s.count = rec['count'] as number;
    }
    return s;
  }
}