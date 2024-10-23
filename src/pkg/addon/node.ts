
import * as fs from 'fs';
import * as path from 'path';

import type {Argument} from '../addon';

import {toBindings} from './wasm';

const ROOT = path.join(__dirname, '..', '..', '..');
const LIB = path.join(ROOT, 'build', 'lib');

const NODE = [path.join(LIB, 'pkmn.node'), path.join(LIB, 'pkmn-showdown.node')];
const WASM = [path.join(LIB, 'pkmn.wasm'), path.join(LIB, 'pkmn-showdown.wasm')];

export async function load(showdown: boolean, addon?: Argument) {
  if (addon === undefined || typeof addon === 'string' && addon !== 'wasm') {
    try {
      return require(!addon || addon === 'node' ? NODE[+showdown] : addon).engine;
    } catch (err) {
      if (!(err instanceof Error)) return err;
      if (addon && addon !== 'node') {
        throw new Error(`Unable to load native addon: '${addon}'\n${err.message}`);
      } else {
        throw error(NODE[+showdown], err);
      }
    }
  }

  let wasm_exports: WebAssembly.Exports;
  const text_decoder = new TextDecoder();

  let wasm: WebAssembly.Instance;
  if (addon === 'wasm') {
    try {
      wasm = (await WebAssembly.instantiate(fs.readFileSync(WASM[+showdown]), {
        js: {
          log(ptr: number, len: number) {
            if (len === 0) return console.log('');
            const msg = text_decoder.decode(new Uint8Array((
              wasm_exports.memory as WebAssembly.Memory) .buffer, ptr, len));
            console.log(msg);
          },
          panic(ptr: number, len: number) {
            const msg = text_decoder.decode(new Uint8Array((
              wasm_exports.memory as WebAssembly.Memory) .buffer, ptr, len));
            throw new Error('panic: ' + msg);
          },
        },
      })).instance;
      wasm_exports = wasm.exports;
    } catch (err) {
      throw error(WASM[+showdown], err);
    }
  } else if (addon instanceof WebAssembly.Module) {
    try {
      wasm = (await WebAssembly.instantiate(addon));
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      throw new Error(`Could not instantiate WASM module!\n${err.message}`);
    }
  } else {
    try {
      const response = (addon as Promise<Response> | URL) instanceof Promise ? addon : fetch(addon);
      wasm = (await WebAssembly.instantiateStreaming(response)).instance;
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      throw new Error(`Could not instantiate WASM module!\n${err.message}`);
    }
  }

  return toBindings(wasm.exports);
}

export function loadSync(showdown: boolean) {
  try {
    return require(NODE[+showdown]).engine;
  } catch {
    return undefined;
  }
}

function error(file: string, err: unknown) {
  if (!(err instanceof Error)) return err;
  const message = `Could not find ${path.basename(file)} addon`;
  return new Error(`${message} - did you run \`npx install-pkmn-engine\`?\n${err.message}`);
}
