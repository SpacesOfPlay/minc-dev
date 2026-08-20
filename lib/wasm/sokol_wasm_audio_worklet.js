// AudioWorkletProcessor for the wasm sokol_audio backend.

class SaudioWorklet extends AudioWorkletProcessor {
    constructor(opts) {
        super();
        const o = (opts && opts.processorOptions) || {};
        this.numChannels = o.numChannels || 1;
        this.pending = [];
        this.cursor = 0;
        this.port.onmessage = (ev) => {
            this.pending.push(ev.data);
        };
    }

    process(inputs, outputs, params) {
        const out = outputs[0];
        const len = out[0].length;
        const nc = this.numChannels;
        for (let i = 0; i < len; i++) {
            if (this.pending.length === 0) {
                // underflow → silence
                for (let chn = 0; chn < nc; chn++) {
                    const ch = out[chn] || out[0];
                    ch[i] = 0;
                }
                continue;
            }
            const head = this.pending[0];
            for (let chn = 0; chn < nc; chn++) {
                const ch = out[chn] || out[0];
                ch[i] = head[this.cursor + chn];
            }
            this.cursor += nc;
            if (this.cursor >= head.length) {
                this.pending.shift();
                this.cursor = 0;
            }
        }
        return true;
    }
}

registerProcessor('saudio-worklet', SaudioWorklet);
