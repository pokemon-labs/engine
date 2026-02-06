import * as engine from '../../pkg';

import {Fragment} from './dom';
import {Battle, Gen, Generation, adapt} from './ui';
import * as util from './util';

const App = ({gen, data, error, seed}: {
  gen: Generation;
  data: DataView;
  error?: string;
  seed?: bigint;
}) => {
  const frames = util.parse(gen, data, (partial, _, showdown, last) =>
    (<Frame frame={partial || {}} gen={gen} showdown={showdown} last={last} />));
  return <>
    {!!seed && <h1>0x{seed.toString(16).toUpperCase()}</h1>}
    {frames}
    {error && <pre className='error'><code>{error}</code></pre>}
  </>;
};

const Frame = ({frame, gen, showdown, last}: {
  frame: Partial<util.Frame>;
  gen: Generation;
  showdown: boolean;
  last?: engine.Data<engine.Battle>;
}) => <div className='frame'>
  {frame.parsed && <div className='log'>
    <pre><code>{util.toText(frame.parsed)}</code></pre>
  </div>}
  {frame.battle && <Battle battle={frame.battle} gen={gen} showdown={showdown} last={last} />}
  {frame.result && <div className='sides' style={{textAlign: 'center'}}>
    <pre className='side'><code>{frame.result.p1} -&gt; {util.pretty(frame.c1)}</code></pre>
    <pre className='side'><code>{frame.result.p2} -&gt; {util.pretty(frame.c2)}</code></pre>
  </div>}
</div>;

// Data is inlined in the same script tag to save bytes - it would be more proper embed the data in
// a <script type="application/json" id="data">...</script>, however this would force us all of the
// keys to be quoted which wastes space (not to mention parsing the object would then add latency)
const json = (window as any).DATA;
const GEN = adapt(new Gen(json.gen));
// NB: "The Unicode Problem" is not relevant here - we know this isn't Unicode text
// https://developer.mozilla.org/en-US/docs/Glossary/Base64#the_unicode_problem
const buf = Uint8Array.from(atob(json.buf), c => c.charCodeAt(0));
document.getElementById('content')!.appendChild(<App
  gen={GEN}
  data={new DataView(buf.buffer, buf.byteOffset, buf.byteLength)}
  error={json.error}
  seed={json.seed && BigInt(json.seed)}
/>);
