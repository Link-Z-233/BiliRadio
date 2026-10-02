/*
 * QR Code generator (ArkTS port)
 * Ported from Project Nayuki's TypeScript library (MIT License).
 * https://www.nayuki.io/page/qr-code-generator-library
 * Copyright (c) Project Nayuki. (MIT License)
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement.
 */

import { util } from '@kit.ArkTS';

export class QrEcc {
  static readonly LOW: QrEcc = new QrEcc(0, 1);
  static readonly MEDIUM: QrEcc = new QrEcc(1, 0);
  static readonly QUARTILE: QrEcc = new QrEcc(2, 3);
  static readonly HIGH: QrEcc = new QrEcc(3, 2);

  readonly ordinal: number;
  readonly formatBits: number;

  private constructor(ordinal: number, formatBits: number) {
    this.ordinal = ordinal;
    this.formatBits = formatBits;
  }
}

export class QrMode {
  static readonly NUMERIC: QrMode = new QrMode(0x1, [10, 12, 14]);
  static readonly ALPHANUMERIC: QrMode = new QrMode(0x2, [9, 11, 13]);
  static readonly BYTE: QrMode = new QrMode(0x4, [8, 16, 16]);
  static readonly KANJI: QrMode = new QrMode(0x8, [8, 10, 12]);
  static readonly ECI: QrMode = new QrMode(0x7, [0, 0, 0]);

  readonly modeBits: number;
  private readonly numBitsCharCount: number[];

  private constructor(modeBits: number, numBitsCharCount: number[]) {
    this.modeBits = modeBits;
    this.numBitsCharCount = numBitsCharCount;
  }

  numCharCountBits(ver: number): number {
    return this.numBitsCharCount[Math.floor((ver + 7) / 17)];
  }
}

export class QrSegment {
  readonly mode: QrMode;
  readonly numChars: number;
  private readonly bitData: number[];

  constructor(mode: QrMode, numChars: number, bitData: number[]) {
    if (numChars < 0) {
      throw new RangeError('Invalid argument');
    }
    this.mode = mode;
    this.numChars = numChars;
    this.bitData = bitData.slice();
  }

  getData(): number[] {
    return this.bitData.slice();
  }

  static makeBytes(data: number[]): QrSegment {
    const bb: number[] = [];
    for (let i = 0; i < data.length; i++) {
      qrAppendBits(data[i], 8, bb);
    }
    return new QrSegment(QrMode.BYTE, data.length, bb);
  }

  static makeNumeric(digits: string): QrSegment {
    if (!QrSegment.isNumeric(digits)) {
      throw new RangeError('String contains non-numeric characters');
    }
    const bb: number[] = [];
    let i: number = 0;
    while (i < digits.length) {
      const n: number = Math.min(digits.length - i, 3);
      const val: number = parseInt(digits.substring(i, i + n), 10);
      qrAppendBits(val, n * 3 + 1, bb);
      i += n;
    }
    return new QrSegment(QrMode.NUMERIC, digits.length, bb);
  }

  static makeAlphanumeric(text: string): QrSegment {
    if (!QrSegment.isAlphanumeric(text)) {
      throw new RangeError('String contains unencodable characters in alphanumeric mode');
    }
    const bb: number[] = [];
    let i: number = 0;
    while (i + 2 <= text.length) {
      let temp: number = QrSegment.ALPHANUMERIC_CHARSET.indexOf(text.charAt(i)) * 45;
      temp += QrSegment.ALPHANUMERIC_CHARSET.indexOf(text.charAt(i + 1));
      qrAppendBits(temp, 11, bb);
      i += 2;
    }
    if (i < text.length) {
      qrAppendBits(QrSegment.ALPHANUMERIC_CHARSET.indexOf(text.charAt(i)), 6, bb);
    }
    return new QrSegment(QrMode.ALPHANUMERIC, text.length, bb);
  }

  static makeSegments(text: string): QrSegment[] {
    if (text === '') {
      return [];
    }
    if (QrSegment.isNumeric(text)) {
      return [QrSegment.makeNumeric(text)];
    }
    if (QrSegment.isAlphanumeric(text)) {
      return [QrSegment.makeAlphanumeric(text)];
    }
    return [QrSegment.makeBytes(QrSegment.toUtf8ByteArray(text))];
  }

  static getTotalBits(segs: QrSegment[], version: number): number {
    let result: number = 0;
    for (let i = 0; i < segs.length; i++) {
      const seg: QrSegment = segs[i];
      const ccbits: number = seg.mode.numCharCountBits(version);
      if (seg.numChars >= (1 << ccbits)) {
        return 1000000000;
      }
      result += 4 + ccbits + seg.bitData.length;
    }
    return result;
  }

  static isNumeric(text: string): boolean {
    return QrSegment.NUMERIC_REGEX.test(text);
  }

  static isAlphanumeric(text: string): boolean {
    return QrSegment.ALPHANUMERIC_REGEX.test(text);
  }

  private static toUtf8ByteArray(str: string): number[] {
    const encoder: util.TextEncoder = new util.TextEncoder();
    const encoded: Uint8Array = encoder.encodeInto(str);
    const result: number[] = [];
    for (let i = 0; i < encoded.length; i++) {
      result.push(encoded[i]);
    }
    return result;
  }

  private static readonly NUMERIC_REGEX: RegExp = /^[0-9]*$/;
  private static readonly ALPHANUMERIC_REGEX: RegExp = /^[A-Z0-9 $%*+.\/:-]*$/;
  private static readonly ALPHANUMERIC_CHARSET: string = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
}

export class QrCode {
  static encodeText(text: string, ecl: QrEcc): QrCode {
    const segs: QrSegment[] = QrSegment.makeSegments(text);
    return QrCode.encodeSegments(segs, ecl);
  }

  static encodeBinary(data: number[], ecl: QrEcc): QrCode {
    const seg: QrSegment = QrSegment.makeBytes(data);
    return QrCode.encodeSegments([seg], ecl);
  }

  static encodeSegments(segs: QrSegment[], ecl: QrEcc,
    minVersion: number = 1, maxVersion: number = 40,
    mask: number = -1, boostEcl: boolean = true): QrCode {
    if (!(QrCode.MIN_VERSION <= minVersion && minVersion <= maxVersion && maxVersion <= QrCode.MAX_VERSION)
      || mask < -1 || mask > 7) {
      throw new RangeError('Invalid value');
    }

    let version: number = minVersion;
    let dataUsedBits: number = 0;
    for (; ; version++) {
      const dataCapacityBits: number = QrCode.getNumDataCodewords(version, ecl) * 8;
      const usedBits: number = QrSegment.getTotalBits(segs, version);
      if (usedBits <= dataCapacityBits) {
        dataUsedBits = usedBits;
        break;
      }
      if (version >= maxVersion) {
        throw new RangeError('Data too long');
      }
    }

    const boostCandidates: QrEcc[] = [QrEcc.MEDIUM, QrEcc.QUARTILE, QrEcc.HIGH];
    for (let i = 0; i < boostCandidates.length; i++) {
      const newEcl: QrEcc = boostCandidates[i];
      if (boostEcl && dataUsedBits <= QrCode.getNumDataCodewords(version, newEcl) * 8) {
        ecl = newEcl;
      }
    }

    const bb: number[] = [];
    for (let i = 0; i < segs.length; i++) {
      const seg: QrSegment = segs[i];
      qrAppendBits(seg.mode.modeBits, 4, bb);
      qrAppendBits(seg.numChars, seg.mode.numCharCountBits(version), bb);
      const data: number[] = seg.getData();
      for (let j = 0; j < data.length; j++) {
        bb.push(data[j]);
      }
    }

    const dataCapacityBits: number = QrCode.getNumDataCodewords(version, ecl) * 8;
    qrAppendBits(0, Math.min(4, dataCapacityBits - bb.length), bb);
    qrAppendBits(0, (8 - bb.length % 8) % 8, bb);

    let padByte: number = 0xEC;
    while (bb.length < dataCapacityBits) {
      qrAppendBits(padByte, 8, bb);
      padByte ^= 0xEC ^ 0x11;
    }

    const dataCodewords: number[] = [];
    while (dataCodewords.length * 8 < bb.length) {
      dataCodewords.push(0);
    }
    for (let i = 0; i < bb.length; i++) {
      dataCodewords[i >>> 3] |= bb[i] << (7 - (i & 7));
    }

    return new QrCode(version, ecl, dataCodewords, mask);
  }

  readonly version: number;
  readonly errorCorrectionLevel: QrEcc;
  readonly size: number;
  readonly mask: number;
  private readonly modules: boolean[][] = [];
  private isFunction: boolean[][] = [];

  constructor(version: number, ecl: QrEcc, dataCodewords: number[], msk: number) {
    if (version < QrCode.MIN_VERSION || version > QrCode.MAX_VERSION) {
      throw new RangeError('Version value out of range');
    }
    if (msk < -1 || msk > 7) {
      throw new RangeError('Mask value out of range');
    }
    this.version = version;
    this.errorCorrectionLevel = ecl;
    this.size = version * 4 + 17;

    const row: boolean[] = [];
    for (let i = 0; i < this.size; i++) {
      row.push(false);
    }
    for (let i = 0; i < this.size; i++) {
      this.modules.push(row.slice());
      this.isFunction.push(row.slice());
    }

    this.drawFunctionPatterns();
    const allCodewords: number[] = this.addEccAndInterleave(dataCodewords);
    this.drawCodewords(allCodewords);

    if (msk === -1) {
      let minPenalty: number = 1000000000;
      for (let i = 0; i < 8; i++) {
        this.applyMask(i);
        this.drawFormatBits(i);
        const penalty: number = this.getPenaltyScore();
        if (penalty < minPenalty) {
          msk = i;
          minPenalty = penalty;
        }
        this.applyMask(i);
      }
    }
    this.mask = msk;
    this.applyMask(msk);
    this.drawFormatBits(msk);

    this.isFunction = [];
  }

  getModule(x: number, y: number): boolean {
    return 0 <= x && x < this.size && 0 <= y && y < this.size && this.modules[y][x];
  }

  private drawFunctionPatterns(): void {
    for (let i = 0; i < this.size; i++) {
      this.setFunctionModule(6, i, i % 2 === 0);
      this.setFunctionModule(i, 6, i % 2 === 0);
    }

    this.drawFinderPattern(3, 3);
    this.drawFinderPattern(this.size - 4, 3);
    this.drawFinderPattern(3, this.size - 4);

    const alignPatPos: number[] = this.getAlignmentPatternPositions();
    const numAlign: number = alignPatPos.length;
    for (let i = 0; i < numAlign; i++) {
      for (let j = 0; j < numAlign; j++) {
        if (!(i === 0 && j === 0 || i === 0 && j === numAlign - 1 || i === numAlign - 1 && j === 0)) {
          this.drawAlignmentPattern(alignPatPos[i], alignPatPos[j]);
        }
      }
    }

    this.drawFormatBits(0);
    this.drawVersion();
  }

  private drawFormatBits(mask: number): void {
    const data: number = this.errorCorrectionLevel.formatBits << 3 | mask;
    let rem: number = data;
    for (let i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    }
    const bits: number = (data << 10 | rem) ^ 0x5412;

    for (let i = 0; i <= 5; i++) {
      this.setFunctionModule(8, i, qrGetBit(bits, i));
    }
    this.setFunctionModule(8, 7, qrGetBit(bits, 6));
    this.setFunctionModule(8, 8, qrGetBit(bits, 7));
    this.setFunctionModule(7, 8, qrGetBit(bits, 8));
    for (let i = 9; i < 15; i++) {
      this.setFunctionModule(14 - i, 8, qrGetBit(bits, i));
    }

    for (let i = 0; i < 8; i++) {
      this.setFunctionModule(this.size - 1 - i, 8, qrGetBit(bits, i));
    }
    for (let i = 8; i < 15; i++) {
      this.setFunctionModule(8, this.size - 15 + i, qrGetBit(bits, i));
    }
    this.setFunctionModule(8, this.size - 8, true);
  }

  private drawVersion(): void {
    if (this.version < 7) {
      return;
    }

    let rem: number = this.version;
    for (let i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >>> 11) * 0x1F25);
    }
    const bits: number = this.version << 12 | rem;

    for (let i = 0; i < 18; i++) {
      const color: boolean = qrGetBit(bits, i);
      const a: number = this.size - 11 + i % 3;
      const b: number = Math.floor(i / 3);
      this.setFunctionModule(a, b, color);
      this.setFunctionModule(b, a, color);
    }
  }

  private drawFinderPattern(x: number, y: number): void {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const dist: number = Math.max(Math.abs(dx), Math.abs(dy));
        const xx: number = x + dx;
        const yy: number = y + dy;
        if (0 <= xx && xx < this.size && 0 <= yy && yy < this.size) {
          this.setFunctionModule(xx, yy, dist !== 2 && dist !== 4);
        }
      }
    }
  }

  private drawAlignmentPattern(x: number, y: number): void {
    for (let dy = -2; dy <= 2; dy++) {
      for (let dx = -2; dx <= 2; dx++) {
        this.setFunctionModule(x + dx, y + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
      }
    }
  }

  private setFunctionModule(x: number, y: number, isDark: boolean): void {
    this.modules[y][x] = isDark;
    this.isFunction[y][x] = true;
  }

  private addEccAndInterleave(data: number[]): number[] {
    const ver: number = this.version;
    const ecl: QrEcc = this.errorCorrectionLevel;
    if (data.length !== QrCode.getNumDataCodewords(ver, ecl)) {
      throw new RangeError('Invalid argument');
    }

    const numBlocks: number = QrCode.NUM_ERROR_CORRECTION_BLOCKS[ecl.ordinal][ver];
    const blockEccLen: number = QrCode.ECC_CODEWORDS_PER_BLOCK[ecl.ordinal][ver];
    const rawCodewords: number = Math.floor(QrCode.getNumRawDataModules(ver) / 8);
    const numShortBlocks: number = numBlocks - rawCodewords % numBlocks;
    const shortBlockLen: number = Math.floor(rawCodewords / numBlocks);

    const blocks: number[][] = [];
    const rsDiv: number[] = QrCode.reedSolomonComputeDivisor(blockEccLen);
    let k: number = 0;
    for (let i = 0; i < numBlocks; i++) {
      const dat: number[] = data.slice(k, k + shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1));
      k += dat.length;
      const ecc: number[] = QrCode.reedSolomonComputeRemainder(dat, rsDiv);
      if (i < numShortBlocks) {
        dat.push(0);
      }
      blocks.push(dat.concat(ecc));
    }

    const result: number[] = [];
    for (let i = 0; i < blocks[0].length; i++) {
      for (let j = 0; j < blocks.length; j++) {
        if (i !== shortBlockLen - blockEccLen || j >= numShortBlocks) {
          result.push(blocks[j][i]);
        }
      }
    }
    return result;
  }

  private drawCodewords(data: number[]): void {
    if (data.length !== Math.floor(QrCode.getNumRawDataModules(this.version) / 8)) {
      throw new RangeError('Invalid argument');
    }
    let i: number = 0;
    for (let right = this.size - 1; right >= 1; right -= 2) {
      if (right === 6) {
        right = 5;
      }
      for (let vert = 0; vert < this.size; vert++) {
        for (let j = 0; j < 2; j++) {
          const x: number = right - j;
          const upward: boolean = ((right + 1) & 2) === 0;
          const y: number = upward ? this.size - 1 - vert : vert;
          if (!this.isFunction[y][x] && i < data.length * 8) {
            this.modules[y][x] = qrGetBit(data[i >>> 3], 7 - (i & 7));
            i++;
          }
        }
      }
    }
  }

  private applyMask(mask: number): void {
    if (mask < 0 || mask > 7) {
      throw new RangeError('Mask value out of range');
    }
    for (let y = 0; y < this.size; y++) {
      for (let x = 0; x < this.size; x++) {
        let invert: boolean = false;
        if (mask === 0) {
          invert = (x + y) % 2 === 0;
        } else if (mask === 1) {
          invert = y % 2 === 0;
        } else if (mask === 2) {
          invert = x % 3 === 0;
        } else if (mask === 3) {
          invert = (x + y) % 3 === 0;
        } else if (mask === 4) {
          invert = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
        } else if (mask === 5) {
          invert = x * y % 2 + x * y % 3 === 0;
        } else if (mask === 6) {
          invert = (x * y % 2 + x * y % 3) % 2 === 0;
        } else if (mask === 7) {
          invert = ((x + y) % 2 + x * y % 3) % 2 === 0;
        }
        if (!this.isFunction[y][x] && invert) {
          this.modules[y][x] = !this.modules[y][x];
        }
      }
    }
  }

  private getPenaltyScore(): number {
    let result: number = 0;

    for (let y = 0; y < this.size; y++) {
      let runColor: boolean = false;
      let runX: number = 0;
      const runHistory: number[] = [0, 0, 0, 0, 0, 0, 0];
      for (let x = 0; x < this.size; x++) {
        if (this.modules[y][x] === runColor) {
          runX++;
          if (runX === 5) {
            result += QrCode.PENALTY_N1;
          } else if (runX > 5) {
            result++;
          }
        } else {
          this.finderPenaltyAddHistory(runX, runHistory);
          if (!runColor) {
            result += this.finderPenaltyCountPatterns(runHistory) * QrCode.PENALTY_N3;
          }
          runColor = this.modules[y][x];
          runX = 1;
        }
      }
      result += this.finderPenaltyTerminateAndCount(runColor, runX, runHistory) * QrCode.PENALTY_N3;
    }

    for (let x = 0; x < this.size; x++) {
      let runColor: boolean = false;
      let runY: number = 0;
      const runHistory: number[] = [0, 0, 0, 0, 0, 0, 0];
      for (let y = 0; y < this.size; y++) {
        if (this.modules[y][x] === runColor) {
          runY++;
          if (runY === 5) {
            result += QrCode.PENALTY_N1;
          } else if (runY > 5) {
            result++;
          }
        } else {
          this.finderPenaltyAddHistory(runY, runHistory);
          if (!runColor) {
            result += this.finderPenaltyCountPatterns(runHistory) * QrCode.PENALTY_N3;
          }
          runColor = this.modules[y][x];
          runY = 1;
        }
      }
      result += this.finderPenaltyTerminateAndCount(runColor, runY, runHistory) * QrCode.PENALTY_N3;
    }

    for (let y = 0; y < this.size - 1; y++) {
      for (let x = 0; x < this.size - 1; x++) {
        const color: boolean = this.modules[y][x];
        if (color === this.modules[y][x + 1] &&
          color === this.modules[y + 1][x] &&
          color === this.modules[y + 1][x + 1]) {
          result += QrCode.PENALTY_N2;
        }
      }
    }

    let dark: number = 0;
    for (let y = 0; y < this.size; y++) {
      for (let x = 0; x < this.size; x++) {
        if (this.modules[y][x]) {
          dark++;
        }
      }
    }
    const total: number = this.size * this.size;
    const k: number = Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1;
    result += k * QrCode.PENALTY_N4;
    return result;
  }

  private getAlignmentPatternPositions(): number[] {
    if (this.version === 1) {
      return [];
    }
    const numAlign: number = Math.floor(this.version / 7) + 2;
    const step: number = Math.floor((this.version * 8 + numAlign * 3 + 5) / (numAlign * 4 - 4)) * 2;
    const result: number[] = [6];
    let pos: number = this.size - 7;
    while (result.length < numAlign) {
      result.splice(1, 0, pos);
      pos -= step;
    }
    return result;
  }

  private static getNumRawDataModules(ver: number): number {
    if (ver < QrCode.MIN_VERSION || ver > QrCode.MAX_VERSION) {
      throw new RangeError('Version number out of range');
    }
    let result: number = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
      const numAlign: number = Math.floor(ver / 7) + 2;
      result -= (25 * numAlign - 10) * numAlign - 55;
      if (ver >= 7) {
        result -= 36;
      }
    }
    return result;
  }

  private static getNumDataCodewords(ver: number, ecl: QrEcc): number {
    return Math.floor(QrCode.getNumRawDataModules(ver) / 8) -
      QrCode.ECC_CODEWORDS_PER_BLOCK[ecl.ordinal][ver] *
      QrCode.NUM_ERROR_CORRECTION_BLOCKS[ecl.ordinal][ver];
  }

  private static reedSolomonComputeDivisor(degree: number): number[] {
    if (degree < 1 || degree > 255) {
      throw new RangeError('Degree out of range');
    }
    const result: number[] = [];
    for (let i = 0; i < degree - 1; i++) {
      result.push(0);
    }
    result.push(1);

    let root: number = 1;
    for (let i = 0; i < degree; i++) {
      for (let j = 0; j < result.length; j++) {
        result[j] = QrCode.reedSolomonMultiply(result[j], root);
        if (j + 1 < result.length) {
          result[j] ^= result[j + 1];
        }
      }
      root = QrCode.reedSolomonMultiply(root, 0x02);
    }
    return result;
  }

  private static reedSolomonComputeRemainder(data: number[], divisor: number[]): number[] {
    const result: number[] = [];
    for (let i = 0; i < divisor.length; i++) {
      result.push(0);
    }
    for (let i = 0; i < data.length; i++) {
      let front: number = 0;
      const shifted: number | undefined = result.shift();
      if (shifted !== undefined) {
        front = shifted;
      }
      const factor: number = data[i] ^ front;
      result.push(0);
      for (let j = 0; j < divisor.length; j++) {
        result[j] ^= QrCode.reedSolomonMultiply(divisor[j], factor);
      }
    }
    return result;
  }

  private static reedSolomonMultiply(x: number, y: number): number {
    if (x >>> 8 !== 0 || y >>> 8 !== 0) {
      throw new RangeError('Byte out of range');
    }
    let z: number = 0;
    for (let i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >>> 7) * 0x11D);
      z ^= ((y >>> i) & 1) * x;
    }
    return z;
  }

  private finderPenaltyCountPatterns(runHistory: number[]): number {
    const n: number = runHistory[1];
    const core: boolean = n > 0 && runHistory[2] === n && runHistory[3] === n * 3 &&
      runHistory[4] === n && runHistory[5] === n;
    return (core && runHistory[0] >= n * 4 && runHistory[6] >= n ? 1 : 0) +
      (core && runHistory[6] >= n * 4 && runHistory[0] >= n ? 1 : 0);
  }

  private finderPenaltyTerminateAndCount(currentRunColor: boolean, currentRunLength: number,
    runHistory: number[]): number {
    let runLength: number = currentRunLength;
    if (currentRunColor) {
      this.finderPenaltyAddHistory(runLength, runHistory);
      runLength = 0;
    }
    runLength += this.size;
    this.finderPenaltyAddHistory(runLength, runHistory);
    return this.finderPenaltyCountPatterns(runHistory);
  }

  private finderPenaltyAddHistory(currentRunLength: number, runHistory: number[]): void {
    let runLength: number = currentRunLength;
    if (runHistory[0] === 0) {
      runLength += this.size;
    }
    runHistory.pop();
    runHistory.unshift(runLength);
  }

  static readonly MIN_VERSION: number = 1;
  static readonly MAX_VERSION: number = 40;

  private static readonly PENALTY_N1: number = 3;
  private static readonly PENALTY_N2: number = 3;
  private static readonly PENALTY_N3: number = 40;
  private static readonly PENALTY_N4: number = 10;

  private static readonly ECC_CODEWORDS_PER_BLOCK: number[][] = [
    [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
    [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  ];

  private static readonly NUM_ERROR_CORRECTION_BLOCKS: number[][] = [
    [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
    [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
    [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
    [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
  ];
}

function qrAppendBits(val: number, len: number, bb: number[]): void {
  if (len < 0 || len > 31 || val >>> len !== 0) {
    throw new RangeError('Value out of range');
  }
  for (let i = len - 1; i >= 0; i--) {
    bb.push((val >>> i) & 1);
  }
}

function qrGetBit(x: number, i: number): boolean {
  return ((x >>> i) & 1) !== 0;
}
