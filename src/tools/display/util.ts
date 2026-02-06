import {GenderName, MoveName, SpeciesName, TypeName} from '@pkmn/data';

import {Battle, Choice, Data, Info, Log, Lookup, ParsedLine, Result, SideInfo} from '../../pkg';
import {LAYOUT, LE} from '../../pkg/data';
import * as gen1 from '../../pkg/gen1';
import {Generation} from '../../pkg/protocol';

export interface Frame {
  result: Result;
  c1: Choice;
  c2: Choice;
  battle: Data<Battle>;
  parsed: ParsedLine[];
}

export interface Species {
  name: SpeciesName;
  num: number;
  genderRatio: {M: number; F: number};
  gender?: GenderName;
}

export interface Move {
  name: MoveName;
  num: number;
  maxpp: number;
  basePower: number;
  type: TypeName;
}

class SpeciesNames implements Info {
  gen: Generation;
  battle: Battle;

  constructor(gen: Generation, battle: Battle) {
    this.gen = gen;
    this.battle = battle;
  }

  get p1() {
    const [p1] = Array.from(this.battle.sides);
    const team = Array.from(p1.pokemon)
      .sort((a, b) => a.position - b.position)
      .map(p => ({species: p.stored.species}));
    return new SideInfo(this.gen, {name: 'Player 1', team});
  }

  get p2() {
    const [, p2] = Array.from(this.battle.sides);
    const team = Array.from(p2.pokemon)
      .sort((a, b) => a.position - b.position)
      .map(p => ({species: p.stored.species}));
    return new SideInfo(this.gen, {name: 'Player 2', team});
  }
}

const format = (kwVal: any) => typeof kwVal === 'boolean' ? '' : ` ${kwVal as string}`;

const trim = (args: string[]) => {
  while (args.length && !args[args.length - 1]) args.pop();
  return args;
};

const compact = (line: ParsedLine) =>
  [...trim(line.args.slice(0) as string[]), ...Object.keys(line.kwArgs)
    .map(k => `[${k}]${format((line.kwArgs as any)[k])}`)].join('|');

const windowed = (data: DataView, byteOffset: number, byteLength?: number) => {
  const length = byteLength ? byteLength - byteOffset : undefined;
  return new DataView(data.buffer, data.byteOffset + byteOffset, length);
};

export const toText = (parsed: ParsedLine[]) =>
  parsed.length ? `|${parsed.map(compact).join('\n|')}` : '';

export const pretty = (choice?: Choice) => choice
  ? choice.type === 'pass' ? choice.type : `${choice.type} ${choice.data}`
  : '???';

export const imports = (memory: [WebAssembly.Memory], decoder: TextDecoder) => ({
  js: {
    log(ptr: number, len: number) {
      if (len === 0) return console.log('');
      const msg = decoder.decode(new Uint8Array(memory[0].buffer, ptr, len));
      console.log(msg);
    },
    panic(ptr: number, len: number) {
      const msg = decoder.decode(new Uint8Array(memory[0].buffer, ptr, len));
      throw new Error('panic: ' + msg);
    },
  },
});

export const parse = <T>(
  gen: Generation,
  data: DataView,
  frame: (partial: Partial<Frame>, gen: Generation, showdown: boolean, last: Data<Battle>) => T
) => {
  let offset = 0;
  const showdown = !!data.getUint8(offset);
  offset += 2;
  const N = data.getInt16(offset, LE);
  offset += 2;
  const X = data.getInt32(offset, LE);
  offset += 4;

  const lookup = Lookup.get(gen);
  const size = LAYOUT[gen.num - 1].sizes.Battle;
  const deserialize = (d: DataView): Battle => {
    switch (gen.num) {
      case 1: return new gen1.Battle(lookup, d, {inert: true, showdown});
      default: throw new Error(`Unsupported gen: ${gen.num}`);
    }
  };

  const battle = deserialize(windowed(data, offset, offset += size));
  const names = new SpeciesNames(gen, battle);
  const log = new Log(gen, lookup, names);

  let partial: Partial<Frame> | undefined = undefined;
  let last: Data<Battle> = battle;
  const frames: T[] = [];
  while (offset < data.byteLength) {
    partial = {parsed: []};

    if (N !== 0) {
      const it = log.parse(windowed(data, offset))[Symbol.iterator]();
      let r = it.next();
      while (!r.done) {
        partial.parsed!.push(r.value);
        r = it.next();
      }
      offset += N > 0 ? N : r.value;
      if (offset >= data.byteLength) break;
    }

    if (X < 0) {
      while (offset < data.byteLength && data.getUint8(offset++));
    } else {
      offset += X;
    }
    if (offset >= data.byteLength) break;

    partial.battle = deserialize(windowed(data, offset, offset += size));
    if (offset >= data.byteLength) break;

    partial.result = Result.decode(data.getUint8(offset++));
    if (offset >= data.byteLength) break;

    partial.c1 = Choice.decode(data.getUint8(offset++));
    if (offset >= data.byteLength) break;

    partial.c2 = Choice.decode(data.getUint8(offset++));

    frames.push(frame(partial, gen, showdown, last));
    last = partial.battle;
    partial = undefined;
  }
  frames.push(frame(partial || {}, gen, showdown, last));
  return frames;
};
