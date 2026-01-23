## Adding a new Generation

1. **[Research](./RESEARCH.md)** the data structures and code flow
2. Add a `data.zig` file with **basic data types** (`Battle`, `Side`, `Pokemon`, ...) and fields
   - un-optimized - exact layout tweaked in step 11
3. **[Generate](../src/tools/generate.ts) data** files
   - reorder enums for performance
   - update [`Lookup`](../src/pkg/data.ts) if necessary
4. **[Generate](../src/tools/generate.ts) test** files
   - reorganize logically and to match previous generations
   - add in cases for known Pokémon Showdown bugs and cartridge glitches
5. **Copy over shared code/files**
   - copy over `README.md` for new generation
   - copy over imports and public function skeletons in `mechanics.zig`
   - copy `Test` infrastructure and rolls into `test.zig`
   - copy over `helpers.zig`
6. Implement **unit [tests](../src/test/showdown/) against Pokémon Showdown** behavior
   - update Bugs section of generation documentation as bugs are discovered
7. Implement **mechanics** in `mechanics.zig` based on cartridge research
   - update [protocol](../src/lib/common/protocol.zig) as necessary, also updating
     [documentation](PROTOCOL.md), [driver](../src/pkg/protocol.ts), and tests
   - [generate](../src/tools/dump.zig) updated [`protocol.json`](../src/data/protocol.json)
8. Adjust **mechanics for Pokémon Showdown** compatibility
   - track RNG differences and update generation documentation (group all RNG is in `Rolls`)
   - ensure all bugs are tracked in documentation
   - add logic to tests to block any unimplementable effects
9. **Unit test the engine** in both cartridge and Pokémon Showdown compatibility mode
10. Implement a **`MAX_LOGS` unit test**
    - document in [`PROTOCOL.md`](PROTOCOL.md)
    - validate with Z3
11. **Optimize data structures**
    - [generate](../src/tools/dump.zig) updated [`layout.json`](../src/data/layout.json) and
     [`data.json`](../src/data/data.json)
12. Implement **driver serialization/deserialization** and writes tests
13. **Expose API** for new generation
    - update [`pkmn.zig`](../src/lib/pkmn.zig) and bindings in
      [`c.zig`](..src/lib/c.zig)/[`node.zig`](..src/lib/node.zig)/[`wasm.zig`](..src/lib/wasm.zig)
    - update [`pkmn.h`](../src/include/pkmn.h)
    - update [`index.ts`](../src/pkg/index.ts)
14. Write **`helper.zig`** and implement **`choices`** method
    - matching `Choices` code required in [showdown](../src/test/showdown/index.ts)
15. Ensure **[fuzz tests](../src/test/benchmark.zig)** pass
    - update [`fuzz.ts`](../src/test/fuzz.ts) and [`debug.ts`](../src/tools/debug.ts)
16. Ensure **[integration tests](../src/test/integration.ts)** pass
17. Add **`chance.zig`** and **`calc.zig`** files with data types
18. **Instrument code with `Chance` and `Calc` calls**
19. Update **unit tests with `expectProbability`** and ensure chance/calc overrides roundtrip
20. Implement **`transitions` function**
   - add `Rolls` helpers for new generation
   - include `transitions` function call in fuzz tests
   - determine `MAX_FRONTIER_SIZE` and add constants to API
21. **Add support to the JS driver for `calc` and `chance`**
   - update [`layout.json`](../src/data/layout.json) to include offsets required
22. **[Benchmark](../src/test/benchmark.zig)** new generation
23. Finalize **documentation** for generation

## Updating `@pkmn/sim` dependency

1. **Bump** pinned `@pkmn/sim` version in [`package.json`](../package.json) and run `npm install`
2. Run `npm run test:integration`, **update rolls and behavior of Pokémon Showdown tests** in
   [`src/test/showdown`](src/test/showdown)
3. **Update Zig mechanics tests to match** the updates applied to the integration tests
4. **Update Zig engine code** to cause the updated mechanics tests to pass
5. **Update documentation** to match new behavior/bugs
6. **Remove effects from blocklists** and helpers if necessary

## Debugging Tests

### Regression Tests

When debugging a specific regression test, remove the logic from the final `catch` block of the `play` function in [`integration.ts`](../src/test/integration.ts) preventing replays from generating the [`logs/pkmn.html`](../logs/pkmn.html) and [`logs/showdown.html`](../logs/showdown.html) UIs:

 ```diff
-if (!replay) {
 const num = toBigInt(seed);
 const stack = err.stack.replace(ANSI, '');
 errors?.seeds.push(num);
 errors?.stacks.push(stack);
 try {
   console.error('');
   dump(
     gen,
     stack,
     num,
     rawInputLog,
     frames,
     partial,
   );
 } catch (e) {
   console.error(e);
 }
-}
```

### Specific errors

#### Unexpected shuffle

Modify `patch.battle` within [`showdown.ts`](../src/test/showdown.ts):

 ```diff
 battle: (battle: Battle, prng = false, debug = false) => {
 +   const run = battle.runEvent.bind(battle);
 +   battle.runEvent = (...args) => {
 +     console.debug(args[0]);
 +     return run(...args);
 +   };
 battle.trunc = battle.dex.trunc.bind(battle.dex);
```
After you have determined the problematic effects which speed tie you can assign them a priority in `patch.generation`.

#### Mismatched seeds

You can determine RNG advances in the engine by modifying the `Gen56` RNG within [`rng.zig`](src/lib/common/rng.zig) to log:

```patch
pub fn advance(self: *Gen56) void {
+    DEBUG(self.seed);
    self.seed = 0x5D588B656C078965 *% self.seed +% 0x0000000000269EC3;
}
```

Note that **the numbers printed here will not match the seeds from Pokémon Showdown** as they are in
little-endian instead of Pokémon Showdown's big-endian convention. Alternatively, if you wish to see
where the advances are occurring you can add debug prints to each of the `Rolls` at the bottom of
the appropriate `mechanics.zig`:

```diff
pub const Rolls = struct {
    fn speedTie(battle: anytype, options: anytype) !bool {
+      DEBUG(@src());
 ```